#include "authorize.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hiredis/hiredis.h>
#include <mosquitto.h>
#include <mosquitto_plugin.h>

static redisContext *redis_conn = NULL;

// Extract userId from client_id (format: "user_<userId>")
static char* extract_user_id(const char *client_id) {
    if (!client_id) {
        return NULL;
    }
    if (strncmp(client_id, "user_", 5) == 0) {
        return strdup(client_id + 5);
    }
    return strdup(client_id);
}

// Extract serviceId from topic (format: "aop/<serviceId>/...")
static char* extract_service_id(const char *topic) {
    if (!topic || strncmp(topic, "aop/", 4) != 0) {
        return NULL;
    }
    
    const char *start = topic + 4;
    const char *end = strchr(start, '/');
    
    if (!end) {
        return strdup(start);
    }
    
    size_t len = end - start;
    char *service_id = malloc(len + 1);
    if (service_id) {
        memcpy(service_id, start, len);
        service_id[len] = '\0';
    }
    return service_id;
}

// Check if topic matches wildcard pattern
static bool topic_matches_pattern(const char *topic, const char *pattern) {
    const char *t = topic;
    const char *p = pattern;
    
    while (*t && *p) {
        if (*p == '#') {
            return true;
        }
        else if (*p == '+') {
            while (*t && *t != '/') t++;
            while (*p && *p != '/') p++;
        }
        else if (*t == *p) {
            t++;
            p++;
        }
        else {
            return false;
        }
    }
    
    return (*t == '\0' && (*p == '\0' || strcmp(p, "#") == 0));
}

// Layer 1: Validate ACL using Redis
static bool validate_acl(const char *user_id, const char *topic) {
    if (!redis_conn || !user_id || !topic) {
        return false;
    }
    
    char key[256];
    snprintf(key, sizeof(key), "acl:%s", user_id);
    
    redisReply *reply = redisCommand(redis_conn, "SMEMBERS %s", key);
    if (!reply || reply->type != REDIS_REPLY_ARRAY) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "No ACL found for user: %s", user_id);
        if (reply) freeReplyObject(reply);
        return false;
    }
    
    bool matched = false;
    for (size_t i = 0; i < reply->elements; i++) {
        const char *pattern = reply->element[i]->str;
        if (topic_matches_pattern(topic, pattern)) {
            mosquitto_log_printf(MOSQ_LOG_DEBUG, "ACL matched: %s -> %s (pattern: %s)", 
                               user_id, topic, pattern);
            matched = true;
            break;
        }
    }
    
    freeReplyObject(reply);
    
    if (!matched) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "ACL denied: %s -> %s", user_id, topic);
    }
    
    return matched;
}

// Layer 2: Validate Consent using Redis
static bool validate_consent(const char *user_id, const char *service_id) {
    if (!redis_conn || !user_id || !service_id) {
        return false;
    }
    
    char key[256];
    snprintf(key, sizeof(key), "user:%s:consent", user_id);
    
    redisReply *reply = redisCommand(redis_conn, "SISMEMBER %s %s", key, service_id);
    if (!reply) {
        mosquitto_log_printf(MOSQ_LOG_ERR, "Redis error checking consent");
        return false;
    }
    
    bool granted = (reply->type == REDIS_REPLY_INTEGER && reply->integer == 1);
    freeReplyObject(reply);
    
    if (granted) {
        mosquitto_log_printf(MOSQ_LOG_DEBUG, "Consent granted: %s -> service %s", 
                           user_id, service_id);
    } else {
        mosquitto_log_printf(MOSQ_LOG_INFO, "Consent denied: %s -> service %s", 
                           user_id, service_id);
    }
    
    return granted;
}

int authorize_init(const char *redis_host, int redis_port) {
    redis_conn = redisConnect(redis_host, redis_port);
    
    if (!redis_conn || redis_conn->err) {
        mosquitto_log_printf(MOSQ_LOG_ERR, "Redis connection failed: %s", 
                           redis_conn ? redis_conn->errstr : "allocation error");
        return -1;
    }
    
    mosquitto_log_printf(MOSQ_LOG_INFO, "Authorization module initialized (Redis: %s:%d)", 
                       redis_host, redis_port);
    return 0;
}

void authorize_cleanup(void) {
    if (redis_conn) {
        redisFree(redis_conn);
        redis_conn = NULL;
    }
    mosquitto_log_printf(MOSQ_LOG_INFO, "Authorization module cleaned up");
}

bool authorize_access(const char *client_id, const char *topic) {
    if (!client_id || !topic) {
        return false;
    }
    
    char *user_id = extract_user_id(client_id);
    if (!user_id) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "Invalid client_id format: %s", client_id);
        return false;
    }
    
    if (!validate_acl(user_id, topic)) {
        free(user_id);
        return false;
    }
    
    if (strncmp(topic, "aop/", 4) == 0) {
        char *service_id = extract_service_id(topic);
        if (service_id) {
            bool consent_ok = validate_consent(user_id, service_id);
            free(service_id);
            free(user_id);
            return consent_ok;
        }
    }
    
    free(user_id);
    return true;
}

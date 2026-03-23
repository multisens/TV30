#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <json-c/json.h>
#include <mosquitto.h>
#include <mosquitto_plugin.h>
#include <mosquitto_broker.h>
#include <mqtt_protocol.h>
#include "schema_validator.h"
#include "response_time_tester.h"
#include "authorize.h"

mosquitto_plugin_id_t *mosq_pid = NULL;
static json_object *schemas = NULL;

// Load schemas from file
static void load_schemas_from_file(const char* filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        mosquitto_log_printf(MOSQ_LOG_WARNING, "Could not open schemas file: %s", filename);
        return;
    }
    
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    char *content = malloc(length + 1);
    fread(content, 1, length, file);
    content[length] = '\0';
    fclose(file);
    
    json_object *new_schemas = json_tokener_parse(content);
    free(content);
    
    if (new_schemas) {
        if (schemas) {
            json_object_put(schemas);
        }
        schemas = new_schemas;
        json_object_get(schemas);
        
        mosquitto_log_printf(MOSQ_LOG_INFO, "Schemas loaded from file: %d topics configured", json_object_object_length(schemas));
        
        json_object_object_foreach(schemas, key, val) {
            mosquitto_log_printf(MOSQ_LOG_INFO, "Schema loaded for topic: %s", key);
        }
    } else {
        mosquitto_log_printf(MOSQ_LOG_ERR, "Invalid JSON in schemas file: %s", filename);
    }
}

// Publish error to errors/<client_id> topic
static void publish_error(const char* topic, const char* error_type, const char* details, const char* payload, const char* client_id) {
    char *error_buffer = malloc(2048);
    if (!error_buffer) return;
    
    time_t now = time(NULL);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S", gmtime(&now));
    
    int len = snprintf(error_buffer, 2048,
        "{\"timestamp\":\"%s\",\"topic\":\"%s\",\"error_type\":\"%s\",\"details\":\"%s\",\"client_id\":\"%s\"%s%s%s}",
        timestamp, topic, error_type, details, 
        client_id ? client_id : "unknown",
        payload ? ",\"payload\":\"" : "",
        payload ? payload : "",
        payload ? "\"" : ""
    );
    
    if (len > 0 && len < 2048) {
        char error_topic[256];
        snprintf(error_topic, sizeof(error_topic), "errors/%s", client_id ? client_id : "unknown");
        mosquitto_broker_publish(NULL, error_topic, len, error_buffer, 0, 0, NULL);
    }
}

// Get schema for a specific topic
static json_object* get_schema_for_topic(const char* topic) {
    if (!schemas) return NULL;
    
    json_object *schema;
    if (json_object_object_get_ex(schemas, topic, &schema)) {
        return schema;
    }
    return NULL;
}

// Validate message against schema
static int validate_message(const char* topic, const char* payload, const char* client_id) {
    json_object *schema = get_schema_for_topic(topic);
    if (!schema) {
        return MOSQ_ERR_SUCCESS;
    }
    
    json_object *message = json_tokener_parse(payload);
    if (!message) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "Invalid JSON for topic: %s", topic);
        publish_error(topic, "INVALID_JSON", "Payload is not valid JSON", payload, client_id);
        return MOSQ_ERR_ACL_DENIED;
    }
    
    validation_result result = validate_json_schema(message, schema);
    json_object_put(message);
    
    if (!result.is_valid) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "Validation failed for topic %s: %s", topic, result.error_message);
        publish_error(topic, "SCHEMA_VALIDATION_FAILED", result.error_message, payload, client_id);
        return MOSQ_ERR_ACL_DENIED;
    }
    
    return MOSQ_ERR_SUCCESS;
}

static int callback_acl_check(int event, void *event_data, void *userdata) {
    struct mosquitto_evt_acl_check *ed = event_data;
    const char *client_id = mosquitto_client_id(ed->client);
    
    // Don't validate the errors topics (avoid loops)
    if (ed->access == MOSQ_ACL_WRITE && strncmp(ed->topic, "errors/", 7) == 0) {
        return MOSQ_ERR_SUCCESS;
    }
    
    // Don't validate PluginResponseTime topics (avoid loops)
    if (ed->access == MOSQ_ACL_WRITE && strncmp(ed->topic, "PluginResponseTime", 18) == 0) {
        return MOSQ_ERR_SUCCESS;
    }
    
    // Check for testResponsetime messages on PublisherResponseTime topics
    if (ed->access == MOSQ_ACL_WRITE && strncmp(ed->topic, "PublisherResponseTime", 21) == 0) {
        if (ed->payload && ed->payloadlen > 0) {
            char *payload_str = malloc(ed->payloadlen + 1);
            memcpy(payload_str, ed->payload, ed->payloadlen);
            payload_str[ed->payloadlen] = '\0';
            
            handle_response_time_test(ed->topic, payload_str);
            free(payload_str);
        }
        return MOSQ_ERR_SUCCESS;
    }
    
    // Authorization check (two-layer validation)
    if (!authorize_access(client_id, ed->topic)) {
        mosquitto_log_printf(MOSQ_LOG_INFO, "Authorization denied: %s -> %s", client_id, ed->topic);
        return MOSQ_ERR_ACL_DENIED;
    }
    
    // Only validate PUBLISH operations on sensor topics
    if (ed->access != MOSQ_ACL_WRITE || strncmp(ed->topic, "sensor/", 7) != 0) {
        return MOSQ_ERR_SUCCESS;
    }
    
    if (ed->payload && ed->payloadlen > 0) {
        char *payload_str = malloc(ed->payloadlen + 1);
        memcpy(payload_str, ed->payload, ed->payloadlen);
        payload_str[ed->payloadlen] = '\0';
        
        const char *client_id = mosquitto_client_id(ed->client);
        int result = validate_message(ed->topic, payload_str, client_id);
        free(payload_str);
        
        if (result != MOSQ_ERR_SUCCESS) {
            mosquitto_log_printf(MOSQ_LOG_INFO, "Validation FAILED for topic: %s", ed->topic);
            return MOSQ_ERR_ACL_DENIED;
        }
    }
    
    return MOSQ_ERR_SUCCESS;
}

int mosquitto_plugin_version(int supported_version_count, const int *supported_versions)
{
    return 5;
}

int mosquitto_plugin_init(mosquitto_plugin_id_t *identifier, void **user_data, struct mosquitto_opt *opts, int opt_count)
{
    mosq_pid = identifier;
    
    schemas = json_object_new_object();
    load_schemas_from_file("/mosquitto/config/schemas.json");
    
    // Initialize authorization module with Redis
    const char *redis_host = getenv("REDIS_HOST") ? getenv("REDIS_HOST") : "redis";
    int redis_port = getenv("REDIS_PORT") ? atoi(getenv("REDIS_PORT")) : 6379;
    
    if (authorize_init(redis_host, redis_port) != 0) {
        mosquitto_log_printf(MOSQ_LOG_ERR, "Failed to initialize authorization module");
        return MOSQ_ERR_UNKNOWN;
    }
    
    mosquitto_log_printf(MOSQ_LOG_INFO, "Mosquitto plugin loaded (validation + response time tester + authorization)");
    
    return mosquitto_callback_register(mosq_pid, MOSQ_EVT_ACL_CHECK, callback_acl_check, NULL, NULL);
}

int mosquitto_plugin_cleanup(void *user_data, struct mosquitto_opt *opts, int opt_count)
{
    if (schemas) {
        json_object_put(schemas);
        schemas = NULL;
    }
    
    authorize_cleanup();
    
    mosquitto_log_printf(MOSQ_LOG_INFO, "Mosquitto plugin unloaded");
    return mosquitto_callback_unregister(mosq_pid, MOSQ_EVT_ACL_CHECK, callback_acl_check, NULL);
}

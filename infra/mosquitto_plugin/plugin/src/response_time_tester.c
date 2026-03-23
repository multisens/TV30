#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <json-c/json.h>
#include <mosquitto.h>
#include <mosquitto_broker.h>

extern mosquitto_plugin_id_t *mosq_pid;

static char* format_timestamp() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm *tm_info = localtime(&tv.tv_sec);
    
    char *time_str = malloc(64);
    if (!time_str) return NULL;
    
    snprintf(time_str, 64, "%04d-%02d-%02d %02d:%02d:%02d.%03ld",
             tm_info->tm_year + 1900, tm_info->tm_mon + 1, tm_info->tm_mday,
             tm_info->tm_hour, tm_info->tm_min, tm_info->tm_sec, tv.tv_usec / 1000);
    
    return time_str;
}

static long long calculate_diff_time(const char *publisher_time_str) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    
    struct tm pub_tm = {0};
    int pub_ms = 0;
    sscanf(publisher_time_str, "%d-%d-%d %d:%d:%d.%d",
           &pub_tm.tm_year, &pub_tm.tm_mon, &pub_tm.tm_mday,
           &pub_tm.tm_hour, &pub_tm.tm_min, &pub_tm.tm_sec, &pub_ms);
    pub_tm.tm_year -= 1900;
    pub_tm.tm_mon -= 1;
    
    time_t pub_time_sec = mktime(&pub_tm);
    long long pub_time_ms = (long long)pub_time_sec * 1000 + pub_ms;
    long long current_time_ms = (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
    
    return current_time_ms - pub_time_ms;
}

void handle_response_time_test(const char* topic, const char* payload) {
    json_object *message = json_tokener_parse(payload);
    if (!message) return;
    
    json_object *test_flag, *publisher_time, *publisher_id, *iteration;
    if (!json_object_object_get_ex(message, "testResponsetime", &test_flag) ||
        !json_object_object_get_ex(message, "localtime", &publisher_time) ||
        !json_object_object_get_ex(message, "id", &publisher_id) ||
        !json_object_object_get_ex(message, "iteration", &iteration)) {
        json_object_put(message);
        return;
    }
    
    const char *pub_time_str = json_object_get_string(publisher_time);
    const char *id = json_object_get_string(publisher_id);
    int iter = json_object_get_int(iteration);
    
    char *current_time_str = format_timestamp();
    if (!current_time_str) {
        json_object_put(message);
        return;
    }
    
    long long diff_time = calculate_diff_time(pub_time_str);
    
    char response_topic[256];
    snprintf(response_topic, sizeof(response_topic), "PluginResponseTime%s/iteration%d", id, iter);
    
    char *response_buffer = malloc(512);
    if (!response_buffer) {
        free(current_time_str);
        json_object_put(message);
        return;
    }
    
    int len = snprintf(response_buffer, 512,
        "{\"localtime\":\"%s\",\"id\":\"%s\",\"iteration\":%d,\"diffTime\":%lld}",
        current_time_str, id, iter, diff_time);
    
    if (len > 0 && len < 512) {
        mosquitto_broker_publish(NULL, response_topic, len, response_buffer, 0, 0, NULL);
        mosquitto_log_printf(MOSQ_LOG_INFO, "Response time test: topic=%s, diffTime=%lld ms", response_topic, diff_time);
    }
    
    free(current_time_str);
    json_object_put(message);
}

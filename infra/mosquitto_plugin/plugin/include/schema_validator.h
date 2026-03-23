#ifndef JSON_SCHEMA_VALIDATOR_H
#define JSON_SCHEMA_VALIDATOR_H

#include <json-c/json.h>

typedef struct {
    char error_message[512];
    int is_valid;
} validation_result;

// Main validation function
validation_result validate_json_schema(json_object *data, json_object *schema);

#endif

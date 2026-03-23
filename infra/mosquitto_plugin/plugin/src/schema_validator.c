#include "schema_validator.h"
#include <string.h>
#include <regex.h>
#include <math.h>

// Validate type
static int validate_type(json_object *data, const char *expected_type, char *error) {
    json_type actual_type = json_object_get_type(data);
    
    if (strcmp(expected_type, "string") == 0 && actual_type != json_type_string) {
        snprintf(error, 512, "Expected type 'string', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "number") == 0 && actual_type != json_type_double && actual_type != json_type_int) {
        snprintf(error, 512, "Expected type 'number', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "integer") == 0 && actual_type != json_type_int) {
        snprintf(error, 512, "Expected type 'integer', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "boolean") == 0 && actual_type != json_type_boolean) {
        snprintf(error, 512, "Expected type 'boolean', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "object") == 0 && actual_type != json_type_object) {
        snprintf(error, 512, "Expected type 'object', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "array") == 0 && actual_type != json_type_array) {
        snprintf(error, 512, "Expected type 'array', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    if (strcmp(expected_type, "null") == 0 && actual_type != json_type_null) {
        snprintf(error, 512, "Expected type 'null', got '%s'", json_type_to_name(actual_type));
        return 0;
    }
    return 1;
}

// Validate minimum
static int validate_minimum(json_object *data, json_object *schema, char *error) {
    json_object *min_obj;
    if (!json_object_object_get_ex(schema, "minimum", &min_obj)) return 1;
    
    double value = json_object_get_double(data);
    double minimum = json_object_get_double(min_obj);
    
    if (value < minimum) {
        snprintf(error, 512, "Value %.2f is less than minimum %.2f", value, minimum);
        return 0;
    }
    return 1;
}

// Validate maximum
static int validate_maximum(json_object *data, json_object *schema, char *error) {
    json_object *max_obj;
    if (!json_object_object_get_ex(schema, "maximum", &max_obj)) return 1;
    
    double value = json_object_get_double(data);
    double maximum = json_object_get_double(max_obj);
    
    if (value > maximum) {
        snprintf(error, 512, "Value %.2f is greater than maximum %.2f", value, maximum);
        return 0;
    }
    return 1;
}

// Validate exclusiveMinimum
static int validate_exclusive_minimum(json_object *data, json_object *schema, char *error) {
    json_object *min_obj;
    if (!json_object_object_get_ex(schema, "exclusiveMinimum", &min_obj)) return 1;
    
    double value = json_object_get_double(data);
    double minimum = json_object_get_double(min_obj);
    
    if (value <= minimum) {
        snprintf(error, 512, "Value %.2f must be greater than %.2f", value, minimum);
        return 0;
    }
    return 1;
}

// Validate exclusiveMaximum
static int validate_exclusive_maximum(json_object *data, json_object *schema, char *error) {
    json_object *max_obj;
    if (!json_object_object_get_ex(schema, "exclusiveMaximum", &max_obj)) return 1;
    
    double value = json_object_get_double(data);
    double maximum = json_object_get_double(max_obj);
    
    if (value >= maximum) {
        snprintf(error, 512, "Value %.2f must be less than %.2f", value, maximum);
        return 0;
    }
    return 1;
}

// Validate multipleOf
static int validate_multiple_of(json_object *data, json_object *schema, char *error) {
    json_object *mult_obj;
    if (!json_object_object_get_ex(schema, "multipleOf", &mult_obj)) return 1;
    
    double value = json_object_get_double(data);
    double multiple = json_object_get_double(mult_obj);
    
    if (fmod(value, multiple) != 0.0) {
        snprintf(error, 512, "Value %.2f is not a multiple of %.2f", value, multiple);
        return 0;
    }
    return 1;
}

// Validate minLength
static int validate_min_length(json_object *data, json_object *schema, char *error) {
    json_object *min_obj;
    if (!json_object_object_get_ex(schema, "minLength", &min_obj)) return 1;
    
    const char *str = json_object_get_string(data);
    int length = strlen(str);
    int min_length = json_object_get_int(min_obj);
    
    if (length < min_length) {
        snprintf(error, 512, "String length %d is less than minLength %d", length, min_length);
        return 0;
    }
    return 1;
}

// Validate maxLength
static int validate_max_length(json_object *data, json_object *schema, char *error) {
    json_object *max_obj;
    if (!json_object_object_get_ex(schema, "maxLength", &max_obj)) return 1;
    
    const char *str = json_object_get_string(data);
    int length = strlen(str);
    int max_length = json_object_get_int(max_obj);
    
    if (length > max_length) {
        snprintf(error, 512, "String length %d is greater than maxLength %d", length, max_length);
        return 0;
    }
    return 1;
}

// Validate pattern
static int validate_pattern(json_object *data, json_object *schema, char *error) {
    json_object *pattern_obj;
    if (!json_object_object_get_ex(schema, "pattern", &pattern_obj)) return 1;
    
    const char *str = json_object_get_string(data);
    const char *pattern = json_object_get_string(pattern_obj);
    
    regex_t regex;
    int ret = regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB);
    if (ret != 0) {
        snprintf(error, 512, "Invalid regex pattern: %s", pattern);
        regfree(&regex);
        return 0;
    }
    
    ret = regexec(&regex, str, 0, NULL, 0);
    regfree(&regex);
    
    if (ret != 0) {
        snprintf(error, 512, "String '%s' does not match pattern '%s'", str, pattern);
        return 0;
    }
    return 1;
}

// Validate enum
static int validate_enum(json_object *data, json_object *schema, char *error) {
    json_object *enum_obj;
    if (!json_object_object_get_ex(schema, "enum", &enum_obj)) return 1;
    
    int array_len = json_object_array_length(enum_obj);
    for (int i = 0; i < array_len; i++) {
        json_object *enum_val = json_object_array_get_idx(enum_obj, i);
        if (json_object_equal(data, enum_val)) {
            return 1;
        }
    }
    
    snprintf(error, 512, "Value is not in enum");
    return 0;
}

// Validate const
static int validate_const(json_object *data, json_object *schema, char *error) {
    json_object *const_obj;
    if (!json_object_object_get_ex(schema, "const", &const_obj)) return 1;
    
    if (!json_object_equal(data, const_obj)) {
        snprintf(error, 512, "Value does not match const");
        return 0;
    }
    return 1;
}

// Validate minItems
static int validate_min_items(json_object *data, json_object *schema, char *error) {
    json_object *min_obj;
    if (!json_object_object_get_ex(schema, "minItems", &min_obj)) return 1;
    
    int length = json_object_array_length(data);
    int min_items = json_object_get_int(min_obj);
    
    if (length < min_items) {
        snprintf(error, 512, "Array length %d is less than minItems %d", length, min_items);
        return 0;
    }
    return 1;
}

// Validate maxItems
static int validate_max_items(json_object *data, json_object *schema, char *error) {
    json_object *max_obj;
    if (!json_object_object_get_ex(schema, "maxItems", &max_obj)) return 1;
    
    int length = json_object_array_length(data);
    int max_items = json_object_get_int(max_obj);
    
    if (length > max_items) {
        snprintf(error, 512, "Array length %d is greater than maxItems %d", length, max_items);
        return 0;
    }
    return 1;
}

// Validate uniqueItems
static int validate_unique_items(json_object *data, json_object *schema, char *error) {
    json_object *unique_obj;
    if (!json_object_object_get_ex(schema, "uniqueItems", &unique_obj)) return 1;
    
    if (!json_object_get_boolean(unique_obj)) return 1;
    
    int length = json_object_array_length(data);
    for (int i = 0; i < length; i++) {
        json_object *item1 = json_object_array_get_idx(data, i);
        for (int j = i + 1; j < length; j++) {
            json_object *item2 = json_object_array_get_idx(data, j);
            if (json_object_equal(item1, item2)) {
                snprintf(error, 512, "Array contains duplicate items");
                return 0;
            }
        }
    }
    return 1;
}

// Validate minProperties
static int validate_min_properties(json_object *data, json_object *schema, char *error) {
    json_object *min_obj;
    if (!json_object_object_get_ex(schema, "minProperties", &min_obj)) return 1;
    
    int length = json_object_object_length(data);
    int min_props = json_object_get_int(min_obj);
    
    if (length < min_props) {
        snprintf(error, 512, "Object has %d properties, minimum is %d", length, min_props);
        return 0;
    }
    return 1;
}

// Validate maxProperties
static int validate_max_properties(json_object *data, json_object *schema, char *error) {
    json_object *max_obj;
    if (!json_object_object_get_ex(schema, "maxProperties", &max_obj)) return 1;
    
    int length = json_object_object_length(data);
    int max_props = json_object_get_int(max_obj);
    
    if (length > max_props) {
        snprintf(error, 512, "Object has %d properties, maximum is %d", length, max_props);
        return 0;
    }
    return 1;
}

// Forward declaration for recursive validation
static validation_result validate_with_schema(json_object *data, json_object *schema);

// Validate required properties
static int validate_required(json_object *data, json_object *schema, char *error) {
    json_object *required_obj;
    if (!json_object_object_get_ex(schema, "required", &required_obj)) return 1;
    
    int array_len = json_object_array_length(required_obj);
    for (int i = 0; i < array_len; i++) {
        json_object *field_name = json_object_array_get_idx(required_obj, i);
        const char *field = json_object_get_string(field_name);
        
        json_object *field_value;
        if (!json_object_object_get_ex(data, field, &field_value)) {
            snprintf(error, 512, "Missing required property '%s'", field);
            return 0;
        }
    }
    return 1;
}

// Validate properties
static int validate_properties(json_object *data, json_object *schema, char *error) {
    json_object *properties_obj;
    if (!json_object_object_get_ex(schema, "properties", &properties_obj)) return 1;
    
    json_object_object_foreach(data, key, val) {
        json_object *prop_schema;
        if (json_object_object_get_ex(properties_obj, key, &prop_schema)) {
            validation_result result = validate_with_schema(val, prop_schema);
            if (!result.is_valid) {
                snprintf(error, 512, "Property '%s': %s", key, result.error_message);
                return 0;
            }
        }
    }
    return 1;
}

// Validate additionalProperties
static int validate_additional_properties(json_object *data, json_object *schema, char *error) {
    json_object *additional_obj;
    if (!json_object_object_get_ex(schema, "additionalProperties", &additional_obj)) return 1;
    
    // If additionalProperties is false, no extra properties allowed
    if (json_object_get_type(additional_obj) == json_type_boolean && 
        !json_object_get_boolean(additional_obj)) {
        
        json_object *properties_obj;
        json_object_object_get_ex(schema, "properties", &properties_obj);
        
        json_object_object_foreach(data, key, val) {
            if (!properties_obj || !json_object_object_get_ex(properties_obj, key, NULL)) {
                snprintf(error, 512, "Additional property '%s' not allowed", key);
                return 0;
            }
        }
    }
    // If additionalProperties is a schema, validate extra properties against it
    else if (json_object_get_type(additional_obj) == json_type_object) {
        json_object *properties_obj;
        json_object_object_get_ex(schema, "properties", &properties_obj);
        
        json_object_object_foreach(data, key, val) {
            if (!properties_obj || !json_object_object_get_ex(properties_obj, key, NULL)) {
                validation_result result = validate_with_schema(val, additional_obj);
                if (!result.is_valid) {
                    snprintf(error, 512, "Additional property '%s': %s", key, result.error_message);
                    return 0;
                }
            }
        }
    }
    return 1;
}

// Validate array items
static int validate_items(json_object *data, json_object *schema, char *error) {
    json_object *items_obj;
    if (!json_object_object_get_ex(schema, "items", &items_obj)) return 1;
    
    int array_len = json_object_array_length(data);
    
    // If items is a schema, validate all items against it
    if (json_object_get_type(items_obj) == json_type_object) {
        for (int i = 0; i < array_len; i++) {
            json_object *item = json_object_array_get_idx(data, i);
            validation_result result = validate_with_schema(item, items_obj);
            if (!result.is_valid) {
                snprintf(error, 512, "Item at index %d: %s", i, result.error_message);
                return 0;
            }
        }
    }
    // If items is an array of schemas, validate each item against corresponding schema
    else if (json_object_get_type(items_obj) == json_type_array) {
        int schema_len = json_object_array_length(items_obj);
        for (int i = 0; i < array_len && i < schema_len; i++) {
            json_object *item = json_object_array_get_idx(data, i);
            json_object *item_schema = json_object_array_get_idx(items_obj, i);
            validation_result result = validate_with_schema(item, item_schema);
            if (!result.is_valid) {
                snprintf(error, 512, "Item at index %d: %s", i, result.error_message);
                return 0;
            }
        }
    }
    return 1;
}

// Main validation logic
static validation_result validate_with_schema(json_object *data, json_object *schema) {
    validation_result result = {.is_valid = 1, .error_message = ""};
    
    // Validate type
    json_object *type_obj;
    if (json_object_object_get_ex(schema, "type", &type_obj)) {
        const char *type = json_object_get_string(type_obj);
        if (!validate_type(data, type, result.error_message)) {
            result.is_valid = 0;
            return result;
        }
    }
    
    json_type data_type = json_object_get_type(data);
    
    // Number validations
    if (data_type == json_type_int || data_type == json_type_double) {
        if (!validate_minimum(data, schema, result.error_message) ||
            !validate_maximum(data, schema, result.error_message) ||
            !validate_exclusive_minimum(data, schema, result.error_message) ||
            !validate_exclusive_maximum(data, schema, result.error_message) ||
            !validate_multiple_of(data, schema, result.error_message)) {
            result.is_valid = 0;
            return result;
        }
    }
    
    // String validations
    if (data_type == json_type_string) {
        if (!validate_min_length(data, schema, result.error_message) ||
            !validate_max_length(data, schema, result.error_message) ||
            !validate_pattern(data, schema, result.error_message)) {
            result.is_valid = 0;
            return result;
        }
    }
    
    // Array validations
    if (data_type == json_type_array) {
        if (!validate_min_items(data, schema, result.error_message) ||
            !validate_max_items(data, schema, result.error_message) ||
            !validate_unique_items(data, schema, result.error_message) ||
            !validate_items(data, schema, result.error_message)) {
            result.is_valid = 0;
            return result;
        }
    }
    
    // Object validations
    if (data_type == json_type_object) {
        if (!validate_required(data, schema, result.error_message) ||
            !validate_min_properties(data, schema, result.error_message) ||
            !validate_max_properties(data, schema, result.error_message) ||
            !validate_properties(data, schema, result.error_message) ||
            !validate_additional_properties(data, schema, result.error_message)) {
            result.is_valid = 0;
            return result;
        }
    }
    
    // Generic validations
    if (!validate_enum(data, schema, result.error_message) ||
        !validate_const(data, schema, result.error_message)) {
        result.is_valid = 0;
        return result;
    }
    
    return result;
}

// Public API
validation_result validate_json_schema(json_object *data, json_object *schema) {
    return validate_with_schema(data, schema);
}

#ifndef AUTHORIZE_H
#define AUTHORIZE_H

#include <stdbool.h>

/**
 * Initialize authorization module
 * Connects to Redis for ACL and user data
 * 
 * @param redis_host Redis server hostname
 * @param redis_port Redis server port
 * @return 0 on success, -1 on error
 */
int authorize_init(const char *redis_host, int redis_port);

/**
 * Cleanup authorization module
 * Frees all allocated resources
 */
void authorize_cleanup(void);

/**
 * Validate client access to topic (two-layer validation)
 * 
 * Layer 1: ACL validation - checks if topic matches user's ACL patterns
 * Layer 2: Consent validation - checks if serviceId is in user's accessConsent
 * 
 * @param client_id MQTT client ID (format: "user_<userId>")
 * @param topic MQTT topic to access
 * @return true if access granted, false otherwise
 */
bool authorize_access(const char *client_id, const char *topic);

#endif // AUTHORIZE_H

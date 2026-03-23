#!/usr/bin/env python3
import json
import redis
import sys

def migrate_to_redis():
    r = redis.Redis(host='redis', port=6379, decode_responses=True)
    
    # Load ACL
    with open('/mosquitto/config/acl.json', 'r') as f:
        acl_data = json.load(f)
    
    for user_id, patterns in acl_data['acl'].items():
        key = f'acl:{user_id}'
        r.delete(key)
        if patterns:
            r.sadd(key, *patterns)
    
    print(f"Migrated {len(acl_data['acl'])} ACL entries")
    
    # Load userData
    with open('/mosquitto/config/userData.json', 'r') as f:
        user_data = json.load(f)
    
    for user in user_data['users']:
        user_id = user['id']
        
        # Store consent as SET
        consent_key = f'user:{user_id}:consent'
        r.delete(consent_key)
        if 'accessConsent' in user and user['accessConsent']:
            r.sadd(consent_key, *user['accessConsent'])
        
        # Store profile as HASH
        profile_key = f'user:{user_id}:profile'
        r.delete(profile_key)
        profile = {k: str(v) for k, v in user.items() if k not in ['id', 'accessConsent']}
        if profile:
            r.hset(profile_key, mapping=profile)
    
    print(f"Migrated {len(user_data['users'])} user entries")
    print("Migration completed successfully")

if __name__ == '__main__':
    try:
        migrate_to_redis()
    except Exception as e:
        print(f"Migration failed: {e}", file=sys.stderr)
        sys.exit(1)

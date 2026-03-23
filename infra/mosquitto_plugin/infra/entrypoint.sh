#!/bin/bash
set -e

echo "Waiting for Redis..."
until redis-cli -h ${REDIS_HOST:-redis} -p ${REDIS_PORT:-6379} ping > /dev/null 2>&1; do
  sleep 1
done

echo "Redis is ready. Running migration..."
python3 /usr/local/bin/migrate_to_redis.py

echo "Starting Mosquitto..."
exec /usr/local/sbin/mosquitto -c /mosquitto/config/mosquitto.conf

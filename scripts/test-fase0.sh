#!/bin/bash
# Smoke da fase 0: plugin sem ACL (item 3) + renomes R2/R5.
set -u
cd /mnt/d/Proj_CEFET/TV30

docker compose up -d >/dev/null 2>&1
sleep 8

echo "== log do broker (novo plugin, sem espera de Redis) =="
docker logs mqtt-broker 2>&1 | grep -iE "plugin loaded|Waiting for Redis" | tail -2

echo "== validacao de schema: payload INVALIDO (value=999) deve ser rejeitado =="
docker exec mqtt-broker mosquitto_pub -t 'sensor/room1/temperature' -m '{"value":999}' 2>&1
sleep 1
docker logs mqtt-broker 2>&1 | grep -i "Validation FAILED" | tail -1

echo "== payload VALIDO deve passar =="
docker exec mqtt-broker mosquitto_pub -t 'sensor/room1/temperature' -m '{"value":21}' && echo "publicado OK"

echo "== AoP com modulos renomeados (URLs inalteradas) =="
docker run --rm --network ginga_net alpine:3 sh -c '
  apk add -q curl >/dev/null 2>&1
  for path in / /profile/create; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://aop:8080$path)
    echo "GET $path -> $code"
  done'

echo "== containers =="
docker ps --format '{{.Names}}\t{{.Status}}' | sort | head -14

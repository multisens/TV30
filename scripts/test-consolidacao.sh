#!/bin/bash
# Acceptance of the single edge (edgegateway) and of the consolidated redis.
set -u
cd "$(dirname "$0")/.." || exit 1

echo "== derrubando a stack (com --remove-orphans) =="
docker compose down --remove-orphans >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1
sleep 15

echo; echo "== containers (alvo: 6 continuos TV30) =="
docker ps --format '{{.Names}}\t{{.Status}}' | sort

echo; echo "== redis consolidado =="
docker inspect redis --format 'health={{.State.Health.Status}}'
docker exec redis redis-cli --raw SCARD users:index | xargs echo "users:index SCARD ="
# Function library loaded before the initial load, and the schema audit: a
# finding is a key outside the schema (a manual write or an old volume;
# docs/modelo-redis.md).
docker logs redis 2>&1 | grep -E "biblioteca de funcoes|carga" | tail -2
docker exec redis redis-cli --raw FCALL_RO tv30_versao 0 | xargs echo "funcoes tv30: esquema versao ="
AUD=$(docker exec redis redis-cli --raw FCALL_RO tv30_auditoria 0)
if [ -z "$AUD" ]; then echo "auditoria do esquema: vazia (OK)"
else
  echo "auditoria do esquema: ACHADOS (chave | familia | motivo)"
  printf '%s\n' "$AUD" | awk 'NR%3==1{k=$0} NR%3==2{f=$0} NR%3==0{print "  " k " | " f " | " $0}'
fi
# The commander UI requires a login; the database connection (6379) has no
# password. In redis-commander 0.9.0 the login is not HTTP basic: POST
# /signin exchanges user and password for a token, and GET /connections
# gives 401 without it. The password goes neither in argv nor in the env of
# the test container (ps and docker inspect would show it): it goes by
# standard input to curl (--data-urlencode "password@-").
CMD_USER=$(docker exec redis printenv REDIS_COMMANDER_USER)
export CMD_USER
docker exec redis printenv REDIS_COMMANDER_PASSWORD \
  | docker run --rm -i --network ginga_net -e CMD_USER --entrypoint sh curlimages/curl:8.10.1 -c '
  IFS= read -r p
  u=http://redis:18081
  sem=$(curl -s -m 5 -o /dev/null -w "%{http_code}" $u/connections)
  r=$(printf %s "$p" | curl -s -m 5 -X POST --data-urlencode "username=$CMD_USER" --data-urlencode "password@-" $u/signin)
  tok=$(printf %s "$r" | sed -n "s/.*\"bearerToken\":\"\([^\"]*\)\".*/\1/p")
  com=$(curl -s -m 5 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $tok" $u/connections)
  r=$(printf x%s "$p" | curl -s -m 5 -X POST --data-urlencode "username=$CMD_USER" --data-urlencode "password@-" $u/signin)
  if [ "$sem" = 401 ] && [ -n "$tok" ] && [ "$com" = 200 ] && [ "$r" = "{\"ok\":false}" ]; then
    echo "commander UI OK (sem credencial=401, com credencial=200, senha errada recusada)"
  else
    echo "commander UI FALHA: sem credencial=$sem, token=$([ -n "$tok" ] && echo sim || echo nao), com credencial=$com, senha errada=$(printf %s "$r" | cut -c1-12)"
    [ "$sem" = 200 ] && echo "  (UI aberta: imagem do redis desatualizada? docker compose build redis && docker compose up -d redis)"
  fi'
docker exec redis redis-cli ping | xargs echo "redis-cli ping sem senha (6379 segue aberto) ="
PORTA_CMD=$(docker port redis 18081/tcp | head -1)
echo "commander no host: $PORTA_CMD"
# The commander exiting also brings the redis container down, and the
# restart (unless-stopped) brings it back, healthy after the load.
echo "-- matando o commander (o container do redis deve cair e voltar) --"
REINICIOS_ANTES=$(docker inspect -f '{{.RestartCount}}' redis)
docker exec redis pkill -f redis-commander
for i in $(seq 1 60); do
  [ "$(docker inspect -f '{{.RestartCount}}' redis)" != "$REINICIOS_ANTES" ] \
    && [ "$(docker inspect -f '{{.State.Health.Status}}' redis 2>/dev/null)" = healthy ] && break
  sleep 1
done
echo "reinicios do redis: $REINICIOS_ANTES -> $(docker inspect -f '{{.RestartCount}}' redis) (esperado +1)"
docker ps --filter name=redis --format '{{.Names}} {{.Status}}'
docker exec redis redis-cli ping

echo; echo "== edgegateway: superficies distintas =="
docker run --rm --network ginga_net alpine:3 sh -c '
  wget -q -O- http://edgegateway:44642/health >/dev/null && echo "interna  /health OK"
  wget -q -O- http://edgegateway:44643/health >/dev/null && echo "externa  /health OK"
  wget -q -O- http://edgegateway:8085/specs/openapi-internal.json | head -c 60; echo " ...spec interna OK"
  wget -q -O /dev/null http://edgegateway:8085/ && echo "swagger UI OK"'

# POST /tv3/current-service/users (C.6.14.1) must reach tv3ws through both
# ports; POST /tv3/users, not declared, comes back 404 with a C.3.2 body
# {"error":100,...} (C.3.2.1), not a reset connection (000). The routes
# exclusive to the local client (106 on 44643) are in scripts/test-auth.sh.
echo; echo "== edgegateway: rota declarada x caminho nao declarado =="
docker run --rm --network ginga_net --entrypoint sh curlimages/curl:8.10.1 -c '
  for s in 44642 44643; do
    c=$(curl -s -m 5 -o /tmp/b -D /tmp/h -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "{}" http://edgegateway:$s/tv3/current-service/users)
    w=$(grep -i "^X-TV30-Auth-Warn:" /tmp/h | tr -d "\r")
    echo "POST /tv3/current-service/users porta=$s -> $c $(head -c 80 /tmp/b) $w"
    c=$(curl -s -m 5 -o /tmp/b -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "{}" http://edgegateway:$s/tv3/users)
    echo "POST /tv3/users (nao declarada) porta=$s -> $c $(head -c 80 /tmp/b)"
  done'

echo; echo "== morre-inteiro: matando um krakend interno =="
docker exec edgegateway sh -c 'pkill -f krakend-internal || pkill krakend'
sleep 4
docker ps -a --filter name=edgegateway --format '{{.Names}} {{.Status}}'
docker compose up -d edgegateway >/dev/null 2>&1
sleep 4
docker ps --filter name=edgegateway --format 'religado: {{.Names}} {{.Status}}'

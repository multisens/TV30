#!/bin/bash
# Aceite da borda unica (edgegateway) e do redis consolidado.
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
# biblioteca de funcoes carregada antes da carga inicial, e auditoria do
# esquema: achado = chave fora do esquema (escrita manual ou volume antigo;
# docs/modelo-redis.md)
docker logs redis 2>&1 | grep -E "biblioteca de funcoes|carga" | tail -2
docker exec redis redis-cli --raw FCALL_RO tv30_versao 0 | xargs echo "funcoes tv30: esquema versao ="
AUD=$(docker exec redis redis-cli --raw FCALL_RO tv30_auditoria 0)
if [ -z "$AUD" ]; then echo "auditoria do esquema: vazia (OK)"
else
  echo "auditoria do esquema: ACHADOS (chave | familia | motivo)"
  printf '%s\n' "$AUD" | awk 'NR%3==1{k=$0} NR%3==2{f=$0} NR%3==0{print "  " k " | " f " | " $0}'
fi
# A UI do commander exige login; a conexao com o banco (6379) segue sem senha.
# No redis-commander 0.9.0 o login nao e HTTP basic: POST /signin troca
# usuario/senha por um token, e GET /connections da 401 sem ele. A senha nao
# entra em argv nem em env do container de teste (ps e docker inspect a
# mostrariam): vai pela entrada padrao ate o curl (--data-urlencode "password@-").
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
# morre-inteiro tambem para o commander: o container do redis cai e o restart
# (unless-stopped) o traz de volta, saudavel depois da carga.
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

# POST /tv3/current-service/users (C.6.14.1) tem de chegar ao tv3ws pelas duas
# portas; POST /tv3/users, nao declarada, volta 404 com corpo C.3.2
# {"error":100,...} (C.3.2.1), e nao conexao resetada (000). As exclusivas do
# cliente local (106 na 44643) ficam no scripts/test-auth.sh.
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

#!/bin/bash
# Aceite das fases 2-3: edgegateway (borda unica) + redis consolidado.
set -u
cd "$(dirname "$0")/.." || exit 1

echo "== derrubando stack antigo (leva os 5 extintos junto) =="
docker compose down --remove-orphans >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1
sleep 15

echo; echo "== containers (alvo: 6 continuos TV30) =="
docker ps --format '{{.Names}}\t{{.Status}}' | sort

echo; echo "== redis consolidado =="
docker inspect redis --format 'health={{.State.Health.Status}}'
docker exec redis redis-cli --raw SCARD users:index | xargs echo "users:index SCARD ="
# D-L1 (Luis, 03/10): a UI do commander exige login; a conexao com o banco
# (6379) segue sem senha. No redis-commander 0.9.0 o login nao e HTTP basic:
# GET / (formulario) abre sem credencial; POST /signin troca usuario/senha
# por um token e as rotas de dados respondem 401 sem ele. Prova: rota de
# dados GET /connections -> 401 sem credencial e 200 com a credencial
# configurada (lida do proprio container; a senha nao e impressa).
# A senha nao entra em argv nem em variavel de ambiente do container de
# teste (o ps do host e o docker inspect mostrariam): vai pela entrada
# padrao do docker run, e dali pela entrada padrao do curl
# (--data-urlencode "password@-" le e codifica o stdin); printf e read sao
# internos do shell.
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
    [ "$sem" = 200 ] && echo "  (UI aberta: imagem do redis anterior a D-L1? docker compose build redis && docker compose up -d redis)"
  fi'
docker exec redis redis-cli ping | xargs echo "redis-cli ping sem senha (6379 segue aberto) ="
PORTA_CMD=$(docker port redis 18081/tcp | head -1)
echo "commander no host: $PORTA_CMD"
echo "-- matando o commander (banco deve sobreviver) --"
docker exec redis pkill -f redis-commander
sleep 2
docker ps --filter name=redis --format '{{.Names}} {{.Status}}'
docker exec redis redis-cli ping

echo; echo "== edgegateway: superficies distintas =="
docker run --rm --network ginga_net alpine:3 sh -c '
  wget -q -O- http://edgegateway:44642/health >/dev/null && echo "interna  /health OK"
  wget -q -O- http://edgegateway:44643/health >/dev/null && echo "externa  /health OK"
  wget -q -O- http://edgegateway:8085/specs/openapi-internal.json | head -c 60; echo " ...spec interna OK"
  wget -q -O /dev/null http://edgegateway:8085/ && echo "swagger UI OK"'

# A antiga POST /tv3/users (so na interna) saiu da tabela de rotas (infra
# 8d5949d) e hoje toda rota existe nas duas superficies. Rota existente
# equivalente (POST com corpo JSON): POST /tv3/current-service/users
# (C.6.14.1), que tem de chegar ao tv3ws pelas duas portas. Caminho NAO
# declarado tem de voltar 404 com corpo C.3.2 {"error":100,...} (C.3.2.1),
# nao resetar a conexao (000).
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

#!/bin/bash
# Aceite das fases 2-3: edgegateway (borda unica) + redis consolidado.
set -u
cd /mnt/d/Proj_CEFET/TV30

echo "== derrubando stack antigo (leva os 5 extintos junto) =="
docker compose down --remove-orphans >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1
sleep 15

echo; echo "== containers (alvo: 6 continuos TV30) =="
docker ps --format '{{.Names}}\t{{.Status}}' | sort

echo; echo "== redis consolidado =="
docker inspect redis --format 'health={{.State.Health.Status}}'
docker exec redis redis-cli --raw SCARD users:index | xargs echo "users:index SCARD ="
docker exec redis sh -c 'wget -q -O- http://127.0.0.1:18081/ >/dev/null && echo "commander UI OK"'
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
  # /tv3/users so existe na INTERNA: na externa o krakend responde 404
  ci=$(wget -q -O /dev/null -S http://edgegateway:44642/tv3/users --post-data="{}" 2>&1 | awk "/HTTP\//{print \$2}" | head -1)
  ce=$(wget -q -O /dev/null -S http://edgegateway:44643/tv3/users --post-data="{}" 2>&1 | awk "/HTTP\//{print \$2}" | head -1)
  echo "POST /tv3/users interna=$ci externa=$ce (esperado: interna!=404, externa=404)"
  wget -q -O- http://edgegateway:8085/specs/openapi-internal.json | head -c 60; echo " ...spec interna OK"
  wget -q -O /dev/null http://edgegateway:8085/ && echo "swagger UI OK"'

echo; echo "== morre-inteiro: matando um krakend interno =="
docker exec edgegateway sh -c 'pkill -f krakend-internal || pkill krakend'
sleep 4
docker ps -a --filter name=edgegateway --format '{{.Names}} {{.Status}}'
docker compose up -d edgegateway >/dev/null 2>&1
sleep 4
docker ps --filter name=edgegateway --format 'religado: {{.Names}} {{.Status}}'

#!/bin/bash
# Test of the clean shutdown of bcast: checks the retained topics, times the
# docker stop (it must end well before the 10 s timeout), checks that the
# retained topics were cleared and starts bcast again.
set -u
cd "$(dirname "$0")/.." || exit 1

docker compose up -d bcast mosquitto >/dev/null 2>&1
sleep 6
echo "== retidos ANTES do stop =="
docker exec mqtt-broker mosquitto_sub -t 'tlm/#' -v --retained-only -W 2 2>/dev/null | cut -c1-60

echo "== docker stop bcast (cronometrado) =="
START=$(date +%s%N)
docker stop bcast >/dev/null
END=$(date +%s%N)
echo "stop levou $(( (END-START)/1000000 )) ms"
docker inspect bcast --format 'ExitCode={{.State.ExitCode}}'

sleep 1
echo "== retidos DEPOIS do stop (esperado: vazio) =="
docker exec mqtt-broker mosquitto_sub -t 'tlm/#' -v --retained-only -W 2 2>/dev/null | cut -c1-60
echo "(fim da listagem)"

docker compose up -d bcast >/dev/null 2>&1
sleep 4
echo "== bcast religado =="
docker ps --filter name=bcast --format '{{.Names}} {{.Status}}'
docker exec mqtt-broker mosquitto_sub -t 'tlm/#' -v --retained-only -W 2 2>/dev/null | wc -l

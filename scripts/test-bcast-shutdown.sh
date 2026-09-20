#!/bin/bash
# Teste do shutdown limpo do bcast (item 2 da vacina):
# 1) sobe bcast com a imagem nova; 2) confere topicos retidos publicados;
# 3) docker stop cronometrado (deve encerrar bem antes do timeout de 10s);
# 4) confere que os retidos foram limpos; 5) religa o bcast.
set -u
cd /mnt/d/Proj_CEFET/TV30

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

#!/bin/bash
# Teste temporario: simula maquina virgem (sem ccws/.env e sem user-files)
# e sobe o stack com um unico comando. Restaura o .env ao final.
set -u
cd /mnt/d/Proj_CEFET/TV30

mv ccws/.env /tmp/ccws.env.bak 2>/dev/null && echo "[test] ccws/.env afastado"
mv user-files /tmp/user-files.bak 2>/dev/null && echo "[test] user-files afastado"

docker compose down --remove-orphans >/dev/null 2>&1
echo "[test] stack derrubado; subindo do zero..."
docker compose up -d 2>&1 | tail -5

sleep 12
echo "== preflight =="
docker logs tv30-preflight 2>&1 | tail -8
echo "== userfiles-seed =="
docker logs tv30-userfiles-seed 2>&1
echo "== ccws boot =="
docker logs ccws 2>&1 | head -6
echo "== containers =="
docker ps -a --format '{{.Names}}\t{{.Status}}' | sort
echo "== user-files semeado? =="
ls user-files/

mv /tmp/ccws.env.bak ccws/.env 2>/dev/null && echo "[test] ccws/.env restaurado"
echo "[test] fim"

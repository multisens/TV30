#!/bin/bash
# Teste temporario: simula maquina virgem (sem tv3ws/.env e sem user-files)
# e sobe o stack com um unico comando.
#
# ATENCAO: derruba a stack (down --remove-orphans) e a sobe do zero.
# No fim (trap EXIT, inclusive em erro ou Ctrl+C) devolve o tv3ws/.env e o
# CONTEUDO original de ./user-files (perfis e thumbs do usuario; o semeado
# pelo teste e descartado) e recria tv3ws e aop, que leem os dois, para a
# stack voltar a usar os dados originais. O backup fica num diretorio de
# mktemp; se a restauracao falhar, o caminho dele e impresso.
set -u
cd "$(dirname "$0")/.." || exit 1

BAK=$(mktemp -d "${TMPDIR:-/tmp}/tv30-virgin-up.XXXXXX") || exit 1
HAD_ENV=0; HAD_UF=0

restore() {
  set +e
  local ok=1
  if [ "$HAD_UF" = 1 ]; then
    # restaura o CONTEUDO (nao o diretorio): os containers montam
    # ./user-files por bind, e trocar o diretorio deixaria a montagem
    # apontando para o semeado ja apagado
    mkdir -p user-files
    find user-files -mindepth 1 -maxdepth 1 -exec rm -rf {} + \
      && cp -a "$BAK/user-files/." user-files/ \
      && echo "[test] user-files original restaurado" \
      || { ok=0; echo "[test] ERRO restaurando user-files: o original esta em $BAK/user-files"; }
  fi
  if [ "$HAD_ENV" = 1 ]; then
    cp -p "$BAK/tv3ws.env" tv3ws/.env \
      && echo "[test] tv3ws/.env restaurado" \
      || { ok=0; echo "[test] ERRO restaurando tv3ws/.env: o original esta em $BAK/tv3ws.env"; }
  fi
  if [ "$ok" = 1 ]; then
    if [ "$HAD_ENV$HAD_UF" != 00 ] && [ "$(docker inspect -f '{{.State.Running}}' tv3ws 2>/dev/null)" = true ]; then
      docker compose up -d --force-recreate --no-deps tv3ws aop >/dev/null 2>&1 \
        && echo "[test] tv3ws e aop recriados com os dados originais" \
        || echo "[test] ATENCAO: recrie tv3ws e aop (docker compose up -d --force-recreate tv3ws aop)"
    fi
    rm -rf "$BAK"
  fi
  echo "[test] fim"
}
trap restore EXIT
trap 'exit 130' INT TERM

if [ -f tv3ws/.env ]; then
  cp -p tv3ws/.env "$BAK/tv3ws.env" && rm -f tv3ws/.env || exit 1
  HAD_ENV=1; echo "[test] tv3ws/.env afastado (copia em $BAK)"
fi
if [ -d user-files ]; then
  cp -a user-files "$BAK/user-files" || exit 1
  HAD_UF=1
  find user-files -mindepth 1 -maxdepth 1 -exec rm -rf {} + || exit 1
  rmdir user-files || exit 1
  echo "[test] user-files afastado (copia em $BAK)"
fi

docker compose down --remove-orphans >/dev/null 2>&1
echo "[test] stack derrubado; subindo do zero..."
docker compose up -d 2>&1 | tail -5

sleep 12
echo "== preflight =="
docker logs tv30-preflight 2>&1 | tail -8
echo "== userfiles-seed =="
docker logs tv30-userfiles-seed 2>&1
echo "== tv3ws boot =="
docker logs tv3ws 2>&1 | head -6
echo "== containers =="
docker ps -a --format '{{.Names}}\t{{.Status}}' | sort
echo "== user-files semeado? =="
ls user-files/

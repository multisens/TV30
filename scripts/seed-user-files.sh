#!/bin/sh
# Semeia ./user-files a partir do template na primeira subida (one-shot,
# idempotente). Elimina o pre-requisito manual de criar a pasta antes do
# `docker compose up`. Nao sobrescreve dados existentes.
set -eu

DEST=/user-files
TPL=/template

mkdir -p "$DEST/thumbs"

if [ ! -f "$DEST/userData.json" ]; then
  cp "$TPL/userData.json" "$DEST/userData.json"
  echo "[userfiles-seed] userData.json copiado do template."
else
  echo "[userfiles-seed] userData.json ja existe — mantido."
fi
echo "[userfiles-seed] ok."

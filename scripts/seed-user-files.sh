#!/bin/sh
# Semeia ./user-files a partir do template (one-shot do servico userfiles-seed
# do compose da raiz, a cada subida; idempotente). Elimina o pre-requisito
# manual de criar a pasta antes do `docker compose up`. Nao sobrescreve dados
# existentes: arquivo que ja esta em ./user-files fica como esta.
#
# G8 (decisao do Luis em 12/10): alem de semear a pasta ausente, copia do
# template os arquivos que FALTAM, para que uma instalacao existente ganhe os
# arquivos novos do template, como o avatar do perfil da carga inicial
# (thumbs/c3167a18-5dc5-4a6e-9b1d-3f2a7c5e8d10.svg; o campo avatar do perfil
# guarda so o nome do arquivo, infra/redis/esquema.json). Ate 12/10 so o
# userData.json era copiado, e so quando faltava. Efeito: arquivo do template
# apagado de ./user-files volta na subida seguinte (ex.: o avatar do perfil da
# carga depois do despejo dele, P3; fica um arquivo que nenhum perfil cita, e
# a C.6.14.6 nao o entrega, porque so serve o avatar de um perfil).
set -eu

DEST=/user-files
TPL=/template

mkdir -p "$DEST/thumbs"

copiados=0
mantidos=0
# lista antes do laco (o laco fica no shell corrente e conta); nome com quebra
# de linha nao funciona (o template nao tem)
LISTA=$(cd "$TPL" && find . -type f | sed 's|^\./||' | sort)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -e "$DEST/$f" ] || [ -L "$DEST/$f" ]; then
    mantidos=$((mantidos + 1))
    echo "[userfiles-seed] $f ja existe — mantido."
  else
    mkdir -p "$(dirname "$DEST/$f")"
    cp "$TPL/$f" "$DEST/$f"
    copiados=$((copiados + 1))
    echo "[userfiles-seed] $f copiado do template."
  fi
done <<EOF
$LISTA
EOF
echo "[userfiles-seed] ok ($copiados copiado(s), $mantidos mantido(s))."

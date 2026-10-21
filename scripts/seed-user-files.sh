#!/bin/sh
# Semeia ./user-files a partir do template (one-shot userfiles-seed do compose,
# a cada subida): copia os arquivos que faltam e nao sobrescreve os existentes.
# Arquivo do template apagado de ./user-files volta na subida seguinte.
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

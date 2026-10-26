#!/bin/sh
# Seeds ./user-files from the template, on every startup: copies the missing
# files and does not overwrite existing ones. A template file deleted from
# ./user-files comes back on the next startup.
set -eu

DEST=/user-files
TPL=/template

mkdir -p "$DEST/thumbs"

copiados=0
mantidos=0
# List built before the loop, so that the loop runs in the current shell and
# counts; a name with a line break does not work.
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

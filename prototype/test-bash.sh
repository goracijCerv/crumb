#!/bin/bash
# Prueba automatica del prototipo bash. Usa carpetas y archivos temporales.
T="$(mktemp -d)"
mkdir -p "$T/projA/.git" "$T/projA/sub" "$T/projB/.git" "$T/plain" "$T/crumb"
export CRUMB_HOME="$T/crumb"
export HISTFILE="$T/crumb/global.txt"
export HISTSIZE=1000
SCRIPT="$(cd "$(dirname "$0")" && pwd)/crumb-proto.sh"

# projA = proyecto, projB = carpeta, plain = global
cat > "$T/session.sh" <<EOF
source "$SCRIPT"
echo G0-inicio
CRUMB_ANSWER=3
cd "$T/projA"
echo A1
cd "$T/projA/sub"
echo A2-en-subcarpeta
CRUMB_ANSWER=2
cd "$T/projB"
echo B1
cd "$T/plain"
echo G1
 echo secreto-no-se-guarda
cd "$T/projA"
echo A3-al-volver
exit
EOF

(cd "$T/plain" && bash --norc -i < "$T/session.sh" > "$T/out.txt" 2>&1)
echo "== historiales generados =="
for f in "$T"/crumb/histories/*.txt "$T/crumb/global.txt"; do
  [ -f "$f" ] && { echo "--- $(basename "$f")"; cat "$f"; }
done
echo "== choices =="; cat "$T/crumb/choices-bash.tsv"
echo "(temp: $T)"

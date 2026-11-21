# Prototipo de crumb para bash. Uso: source crumb-proto.sh
# Cambia HISTFILE segun la carpeta/proyecto. Sin Go, solo para validar el enfoque.

CRUMB_HOME="${CRUMB_HOME:-$HOME/.crumb-proto}"
CRUMB_MARKERS=(.git .crumb package.json go.mod Cargo.toml pyproject.toml)
mkdir -p "$CRUMB_HOME/histories"
_crumb_global="${HISTFILE:-$HOME/.bash_history}"
_crumb_last_pwd=""

# Imprime la raiz del proyecto mas cercana, o falla si no hay.
_crumb_project_root() {
  local d="$PWD" m
  while [ -n "$d" ]; do
    [ "$d" = "$HOME" ] && return 1
    for m in "${CRUMB_MARKERS[@]}"; do
      [ -e "$d/$m" ] && { printf '%s\n' "$d"; return 0; }
    done
    [ "$d" = "/" ] && return 1
    d="$(dirname "$d")"
  done
  return 1
}

_crumb_hist_path() { # $1=ruta clave
  local h; h="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  printf '%s/histories/%s-%s.bash.txt\n' "$CRUMB_HOME" "$(basename "$1")" "$h"
}

_crumb_choice() { # $1=clave -> imprime el modo guardado
  [ -f "$CRUMB_HOME/choices-bash.tsv" ] || return 0
  awk -F'\t' -v k="$1" '$1==k {m=$2} END {if (m) print m}' "$CRUMB_HOME/choices-bash.tsv"
}

# Pregunta el modo. Escribe el menu en stderr para no ensuciar stdout.
_crumb_ask() { # $1=clave $2=hay_proyecto(0/1)
  local ans
  if [ -n "$CRUMB_ANSWER" ]; then ans="$CRUMB_ANSWER"
  elif [ -t 0 ]; then
    {
      printf '\n[crumb] Primera vez en: %s\n' "$1"
      printf '  1) global   2) por carpeta'
      [ "$2" = 1 ] && printf '   3) por proyecto'
      printf '\n  Eleccion [1]: '
    } >&2
    read -r ans
  else ans=1; fi
  case "$ans" in
    2|folder)  echo folder ;;
    3|project) [ "$2" = 1 ] && echo project || echo folder ;;
    *)         echo global ;;
  esac
}

_crumb_resolve() {
  local root key mode hasp=0
  root="$(_crumb_project_root)" && hasp=1
  key="${root:-$PWD}"
  mode="$(_crumb_choice "$key")"
  # Fuera de un proyecto no se pregunta: se usa el global salvo eleccion guardada.
  if [ -z "$mode" ] && [ "$hasp" = 0 ]; then
    mode=global
  elif [ -z "$mode" ]; then
    mode="$(_crumb_ask "$key" "$hasp")"
    printf '%s\t%s\n' "$key" "$mode" >> "$CRUMB_HOME/choices-bash.tsv"
  fi
  case "$mode" in
    project) _crumb_hist_path "$key" ;;
    folder)  _crumb_hist_path "$PWD" ;;
    *)       printf '%s\n' "$_crumb_global" ;;
  esac
}

_crumb_switch() {
  [ "$PWD" = "$_crumb_last_pwd" ] && return
  _crumb_last_pwd="$PWD"
  local f; f="$(_crumb_resolve)" || return
  if [ "$f" != "$HISTFILE" ]; then
    history -a          # guarda lo pendiente en el archivo actual
    HISTFILE="$f"
    history -c
    history -r          # carga el historial nuevo
  fi
}

_crumb_prompt() { _crumb_switch; history -a; }

HISTCONTROL="ignorespace${HISTCONTROL:+:$HISTCONTROL}"
case ";$PROMPT_COMMAND;" in
  *";_crumb_prompt;"*) ;;
  *) PROMPT_COMMAND="_crumb_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

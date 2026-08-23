#!/usr/bin/env bash
#
# Puts `origin` on PATH for use outside an agent.
#
# Installing the plugin through Claude Code or Codex is enough to get the slash
# commands; this is for the terminal, where the same script is the point. It
# symlinks rather than copies, so a `git pull` here is the update.
#
#   ./install.sh              link into ~/.local/bin
#   ./install.sh --prefix DIR link somewhere else
#   ./install.sh --uninstall  take it away

set -euo pipefail

self() {
  local source="${BASH_SOURCE[0]}" directory
  while [ -L "$source" ]; do
    directory="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    case "$source" in
      /*) ;;
      *) source="${directory}/${source}" ;;
    esac
  done
  cd -P "$(dirname "$source")" && pwd
}

ROOT="$(self)"
PREFIX="${ORIGIN_PREFIX:-${HOME}/.local/bin}"
UNINSTALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -gt 1 ] || {
        printf 'install.sh: --prefix needs a directory\n' >&2
        exit 1
      }
      PREFIX="$2"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h | --help)
      sed -n '3,12p' "${ROOT}/install.sh" | sed -e 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'install.sh: unknown argument %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

LINK="${PREFIX}/origin"

if [ "$UNINSTALL" = 1 ]; then
  if [ -L "$LINK" ]; then
    rm "$LINK"
    printf 'Removed %s\n' "$LINK"
  else
    printf 'Nothing to remove at %s\n' "$LINK"
  fi
  exit 0
fi

[ -x "${ROOT}/bin/origin" ] || {
  printf 'install.sh: %s/bin/origin is not executable\n' "$ROOT" >&2
  exit 1
}

mkdir -p "$PREFIX"

# An existing file that is not our symlink is somebody else's, and this is not
# the place to find that out by overwriting it.
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  printf 'install.sh: %s exists and is not a symlink; move it first\n' "$LINK" >&2
  exit 1
fi

ln -sf "${ROOT}/bin/origin" "$LINK"
printf 'Linked %s -> %s\n' "$LINK" "${ROOT}/bin/origin"

# shellcheck disable=SC2016  # $PATH is literal here: it is advice to paste
case ":${PATH}:" in
  *":${PREFIX}:"*) ;;
  *) printf '\n%s is not on your PATH. Add it:\n  export PATH="%s:$PATH"\n' "$PREFIX" "$PREFIX" ;;
esac

"$LINK" --version

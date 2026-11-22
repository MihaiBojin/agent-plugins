#!/bin/sh
set -eu

usage() {
  echo 'Usage: sh pin-count.sh --manifest FILE'
  echo 'Count the package pins in FILE.'
}

if [ "${1-}" = "--help" ]; then
  usage
  exit 0
fi
if [ "$#" -ne 2 ] || [ "$1" != "--manifest" ]; then
  echo "pin-count: expected --manifest FILE (see --help)" >&2
  exit 2
fi

awk 'NF && !/^#/ { n++ } END { print n + 0 }' "$2"

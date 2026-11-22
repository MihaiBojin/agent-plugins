#!/bin/sh
set -eu

usage() {
  echo 'Usage: sh level-count.sh --level LEVEL LOGFILE'
  echo 'Count records beginning with LEVEL (INFO, WARN or ERROR).'
}

if [ "${1-}" = "--help" ]; then
  usage
  exit 0
fi
if [ "$#" -ne 3 ] || [ "$1" != "--level" ]; then
  usage >&2
  exit 2
fi
case "$2" in
  INFO|WARN|ERROR) ;;
  *) usage >&2; exit 2 ;;
esac

awk -v level="$2" '$1 == level { n++ } END { printf "%s=%d\n", level, n }' "$3"

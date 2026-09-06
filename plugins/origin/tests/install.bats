#!/usr/bin/env bats
#
# The installer, which is the one script here that runs before anything else is
# on PATH - and the one whose mistakes land outside the repository.

load helpers/repo

setup() {
  setup_repo
  INSTALL="${BATS_TEST_DIRNAME}/../install.sh"
  PREFIX="${ROOT}/prefix"
  export INSTALL PREFIX
  mkdir -p "$PREFIX"
}

@test "install links, and re-installing over its own link is fine" {
  run "$INSTALL" --prefix "$PREFIX"
  [ "$status" -eq 0 ]
  [ -L "${PREFIX}/origin" ]

  run "$INSTALL" --prefix "$PREFIX"
  [ "$status" -eq 0 ]
  [ -L "${PREFIX}/origin" ]
}

@test "install refuses a regular file already at the target" {
  printf 'not ours\n' >"${PREFIX}/origin"
  run "$INSTALL" --prefix "$PREFIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a symlink"* ]]
  [ -f "${PREFIX}/origin" ]
}

@test "uninstall removes the link this checkout made" {
  "$INSTALL" --prefix "$PREFIX"
  run "$INSTALL" --prefix "$PREFIX" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed"* ]]
  [ ! -L "${PREFIX}/origin" ]
}

# Two clones, --uninstall run from the wrong one. Deleting the other clone's
# link and reporting success is how somebody's install disappears without a
# word; so is calling it "nothing to remove" when it is plainly there.
@test "uninstall leaves a link belonging to another checkout" {
  mkdir -p "${ROOT}/other/bin"
  printf '#!/bin/sh\ntrue\n' >"${ROOT}/other/bin/origin"
  chmod +x "${ROOT}/other/bin/origin"
  ln -s "${ROOT}/other/bin/origin" "${PREFIX}/origin"

  run "$INSTALL" --prefix "$PREFIX" --uninstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"not this checkout"* ]]
  [ -L "${PREFIX}/origin" ]
  [ "$(readlink "${PREFIX}/origin")" = "${ROOT}/other/bin/origin" ]
}

@test "uninstall leaves a link pointing anywhere else at all" {
  ln -s /bin/ls "${PREFIX}/origin"

  run "$INSTALL" --prefix "$PREFIX" --uninstall
  [ "$status" -eq 1 ]
  [ -L "${PREFIX}/origin" ]
}

@test "uninstall leaves a regular file, rather than saying there was nothing" {
  printf 'not ours\n' >"${PREFIX}/origin"

  run "$INSTALL" --prefix "$PREFIX" --uninstall
  [ "$status" -eq 1 ]
  [[ "$output" != *"Nothing to remove"* ]]
  [ -f "${PREFIX}/origin" ]
}

@test "uninstall with nothing there says so and succeeds" {
  run "$INSTALL" --prefix "$PREFIX" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to remove"* ]]
}

# The header was printed by line number, so a line added above line 12 silently
# truncated it. It is bounded by a sentinel now.
@test "--help prints the whole header and none of the script" {
  run "$INSTALL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Puts \`origin\` on PATH"* ]]
  [[ "$output" == *"--uninstall  take it away"* ]]
  [[ "$output" != *"set -euo"* ]]
  [[ "$output" != *"---8<---"* ]]
}

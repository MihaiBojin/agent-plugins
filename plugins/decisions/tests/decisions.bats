#!/usr/bin/env bats
#
# The switch, and the promise that flipping it never deletes a decision.

bats_require_minimum_version 1.5.0

setup() {
  DECISIONS="${BATS_TEST_DIRNAME}/../bin/decisions"
  REPO="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/proj"
  export DECISIONS REPO
  export HOME="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  cd "$REPO" || exit 1
}

@test "enable creates the log with a file git can commit" {
  run "$DECISIONS" enable
  [ "$status" -eq 0 ]
  [[ "$output" == on:* ]]
  [ -f .decisions/.gitkeep ]
  run git check-ignore -q .decisions/.gitkeep
  [ "$status" -eq 1 ]
}

@test "enable warns when the repository ignores the log, and names the diagnostic" {
  printf '.decisions/\n' >.gitignore
  run --separate-stderr "$DECISIONS" enable
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"nothing in it can be committed"* ]]
  [[ "$stderr" == *"git check-ignore -v .decisions/.gitkeep"* ]]
}

@test "disable removes a log that recorded nothing" {
  "$DECISIONS" enable
  run "$DECISIONS" disable
  [ "$status" -eq 0 ]
  [[ "$output" == off:* ]]
  [ ! -d .decisions ]
}

@test "disable keeps every decision file, and marks the log off" {
  "$DECISIONS" enable
  printf '# a topic\n' >.decisions/1788889263-a-topic.md
  run "$DECISIONS" disable
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 topic file(s) kept"* ]]
  [ -f .decisions/1788889263-a-topic.md ]
  [ -f .decisions/.disabled ]
}

@test "enable clears the marker and leaves the files alone" {
  "$DECISIONS" enable
  printf '# a topic\n' >.decisions/1788889263-a-topic.md
  "$DECISIONS" disable
  run "$DECISIONS" enable
  [ "$status" -eq 0 ]
  [[ "$output" == "on: .decisions, 1 topic file(s)" ]]
  [ ! -e .decisions/.disabled ]
  [ -f .decisions/1788889263-a-topic.md ]
}

@test "the log needs a repository, and says so" {
  cd "$BATS_TEST_TMPDIR" || exit 1
  run "$DECISIONS" enable
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "an unknown command prints the usage and fails" {
  run "$DECISIONS" wat
  [ "$status" -eq 1 ]
  [[ "$output" == *"USAGE"* ]]
}

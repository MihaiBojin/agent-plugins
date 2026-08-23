# shellcheck shell=bash
#
# Throwaway repositories, built where bats will delete them. Each test gets its
# own upstream (a local bare repository), its own HOME and git configuration,
# and stub `gh`/`glab` on PATH, so nothing here can reach the network.

# `run --separate-stderr` is how a test checks that stdout carries only data.
bats_require_minimum_version 1.5.0

setup_repo() {
  ORIGIN_BIN="${BATS_TEST_DIRNAME}/../bin/origin"
  # Resolved: on a mac $TMPDIR is a symlink into /private, and every path the
  # plugin prints has been through `pwd -P` or git.
  ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/world"
  UPSTREAM="${ROOT}/upstream.git"
  REPO="${ROOT}/proj"
  WORKTREES="${ROOT}/.worktrees"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  ORIGIN_STUB_DIR="${ROOT}/stub"
  ORIGIN_STUB_LOG="${ROOT}/stub/calls.log"

  export ORIGIN_BIN ROOT UPSTREAM REPO WORKTREES ORIGIN_STUB_DIR ORIGIN_STUB_LOG
  export HOME="$ROOT"
  export GIT_CONFIG_GLOBAL="${ROOT}/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.invalid
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.invalid
  export NO_COLOR=1
  export PATH="${STUBS}:${PATH}"

  mkdir -p "$ROOT" "$ORIGIN_STUB_DIR"
  : >"$GIT_CONFIG_GLOBAL"
  : >"$ORIGIN_STUB_LOG"

  git init -q -b main --bare "$UPSTREAM"
  git clone -q "$UPSTREAM" "$REPO" 2>/dev/null
  cd "$REPO" || return 1

  printf 'hello\n' >README.md
  git add README.md
  git commit -qm "First commit"
  git push -q origin main
  git remote set-head origin --auto >/dev/null 2>&1 || true
}

# A second repository beside the first, sharing the worktree root.
sibling_repo() {
  local name="$1" path="${ROOT}/${1}"
  git init -q -b main "$path"
  (
    cd "$path" || exit 1
    printf 'hi\n' >README.md
    git add README.md
    git commit -qm "First commit"
  )
  printf '%s\n' "$path"
}

origin_cli() {
  run --separate-stderr "$ORIGIN_BIN" "$@"
}

commit_file() {
  local path="$1" contents="$2" message="${3:-Add ${1}}"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$contents" >"$path"
  git add "$path"
  git commit -qm "$message"
}

# A branch whose change reaches main as one squashed commit.
squash_merge_branch() {
  git checkout -q main
  git merge -q --squash "$1"
  git commit -qm "$(printf 'Squash %s' "$1")"
  git push -q origin main
  git fetch -q origin
}

# Make the repository look like it is on a forge while the transport still
# reaches the bare repository next door.
stub_forge() {
  local remote="$1"
  git remote set-url origin "$remote"
  git config "url.${UPSTREAM}.insteadOf" "$remote"
}

stub_json() {
  cat >"${ORIGIN_STUB_DIR}/${1}"
}

# jq over something a test captured, without smuggling it through a quote.
jq_of() {
  printf '%s' "$1" | jq -r "$2"
}

grep_count() {
  grep -c -- "$1" "$2" || true
}

# Somebody else pushes to the head branch, from a clone of their own.
upstream_moves() {
  local path="${1:-elsewhere.txt}" contents="${2:-theirs}" message="${3:-A commit from somewhere else}"
  local other="${ROOT}/other-clone"
  rm -rf "$other"
  git clone -q "$UPSTREAM" "$other"
  (
    cd "$other" || exit 1
    printf '%s\n' "$contents" >"$path"
    git add "$path"
    git commit -qm "$message"
    git push -q origin HEAD:main
  )
  rm -rf "$other"
}

#!/usr/bin/env bats
#
# Which remote, which branch, which forge.

load helpers/repo

setup() {
  setup_repo
  # shellcheck source=../lib/common.sh
  . "${BATS_TEST_DIRNAME}/../lib/common.sh"
  # shellcheck source=../lib/repo.sh
  . "${BATS_TEST_DIRNAME}/../lib/repo.sh"
  # shellcheck source=../lib/forge.sh
  . "${BATS_TEST_DIRNAME}/../lib/forge.sh"
}

@test "the only remote is the one, whatever it is called" {
  git remote rename origin upstream
  run repo_remote
  [ "$output" = "upstream" ]
}

@test "several remotes with nothing to choose between them is refused, with the fix" {
  git remote add upstream "$UPSTREAM"
  # The clone recorded branch.main.remote, which is a legitimate signal and
  # would otherwise answer before the ambiguity is reached.
  git config --unset branch.main.remote
  run repo_remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"git config checkout.defaultRemote"* ]]
}

@test "the retired git-worktree-plugin.remote is ignored, not obeyed" {
  git remote add upstream "$UPSTREAM"
  git config --unset branch.main.remote
  git config git-worktree-plugin.remote upstream
  run repo_remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"git config checkout.defaultRemote"* ]]
}

@test "checkout.defaultRemote is honoured, as git's own knob for this" {
  git remote add upstream "$UPSTREAM"
  git config checkout.defaultRemote upstream
  run repo_remote
  [ "$output" = "upstream" ]
}

@test "remote.pushDefault names the push target, so it does not resolve the base" {
  git remote add upstream "$UPSTREAM"
  git config remote.pushDefault upstream
  run repo_remote
  [ "$output" != "upstream" ]
}

@test "github.com over https and over ssh is GitHub" {
  stub_forge https://github.com/owner/repo.git
  run forge_kind
  [ "$output" = "github" ]

  FORGE_KIND=''
  stub_forge git@github.com:owner/repo.git
  run forge_kind
  [ "$output" = "github" ]
}

@test "a self-hosted GitLab is GitLab" {
  stub_forge https://gitlab.example.com/group/project.git
  run forge_kind
  [ "$output" = "gitlab" ]
}

@test "an unknown host nobody is signed in to is no forge, and is not an error" {
  stub_forge https://git.sr.ht/~someone/project
  run forge_kind
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "an unknown host gh is signed in to is GitHub, without being told" {
  stub_forge https://git.company.example/team/project.git
  export ORIGIN_STUB_HOST=git.company.example
  run forge_kind
  [ "$output" = "github" ]
}

@test "an unknown host glab is signed in to is GitLab" {
  stub_forge https://code.internal.example/team/project.git
  export ORIGIN_STUB_HOST=code.internal.example
  export ORIGIN_STUB_GH_UNAUTHENTICATED=1
  run forge_kind
  [ "$output" = "gitlab" ]
}

@test "an unrecognised remote says which host and which command fixes it" {
  stub_forge https://git.sr.ht/~someone/project
  run forge_require
  [ "$status" -eq 1 ]
  [[ "$output" == *"git.sr.ht"* ]]
  [[ "$output" == *"auth login --hostname"* ]]
}

@test "the head branch comes from the remote" {
  run repo_head_branch
  [ "$output" = "main" ]
}

@test "the head branch is whatever <remote>/HEAD points at" {
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  run repo_head_branch
  [ "$output" = "main" ]
}

@test "the retired git-worktree-plugin.headBranch is ignored, not obeyed" {
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git config git-worktree-plugin.headBranch trunk
  run repo_head_branch
  [ "$output" = "main" ]
}

@test "every branch's state comes back in one call" {
  stub_forge https://github.com/owner/repo.git
  stub_json pr-list.json <<'JSON'
[
  { "number": 1, "headRefName": "merged-one", "state": "MERGED" },
  { "number": 2, "headRefName": "open-one", "state": "OPEN" }
]
JSON

  : >"$ORIGIN_STUB_LOG"
  forge_pr_bulk_load
  [[ "$(forge_pr_state_for merged-one)" == "MERGED"* ]]
  [[ "$(forge_pr_state_for open-one)" == "OPEN"* ]]
  run grep_count "gh pr list" "$ORIGIN_STUB_LOG"
  [ "$output" = "1" ]
}

@test "GitLab calls a pull request a merge request" {
  stub_forge https://gitlab.example.com/group/project.git
  run forge_noun
  [ "$output" = "merge request" ]
}

@test "the ambiguity reaches the user through the CLI, not just the function" {
  git remote add upstream "$UPSTREAM"
  git config --unset branch.main.remote

  run --separate-stderr "$ORIGIN_BIN" gwa feature
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"several remotes"* ]]
  [[ "$stderr" == *"git config checkout.defaultRemote"* ]]
  [ ! -d "${WORKTREES}/feature/proj" ]
}

@test "doctor reports the ambiguity as a failing row rather than dying mid-table" {
  git remote add upstream "$UPSTREAM"
  git config --unset branch.main.remote

  run --separate-stderr "$ORIGIN_BIN" doctor
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"several, and nothing says which"* ]]
  # The rows after it still printed.
  [[ "$stderr" == *"worktree root"* ]]
}

@test "the resolved remote is cached, not recomputed per caller" {
  # shellcheck disable=SC2030,SC2031
  git config checkout.defaultRemote origin
  repo_remote_resolve
  [ "$ORIGIN_REMOTE" = "origin" ]
}

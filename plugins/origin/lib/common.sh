# shellcheck shell=bash
#
# Logging, confirmation, dry-run plumbing, and the rules no subcommand may
# break.
#
# The safety rules live here rather than in each subcommand because a rule
# repeated five times is a rule that holds in four places. Everything that
# mutates a repository goes through `git_run`, which refuses the handful of
# arguments this plugin has decided never to pass.

# Human chatter goes to stderr; only data goes to stdout. That is what makes
# `cd "$(origin wt add foo --quiet)"` work, and what keeps `--json` parseable
# while the same run is explaining itself to a person.

# The separator for rows this plugin passes between its own functions.
#
# Not a tab: `read` treats space, tab and newline as whitespace whatever IFS
# says, so two consecutive tabs collapse into one and every field after an
# empty one shifts left. A worktree with a detached HEAD has an empty branch,
# and that is enough.
ORIGIN_FS=$'\037'

ORIGIN_DRY_RUN=0
ORIGIN_ASSUME_YES=0
ORIGIN_QUIET=0
ORIGIN_VERBOSE=0

# Set only by the one code path that has both an explicit --force and a proof
# that the branch is already in the head branch. Nothing else may raise it.
ORIGIN_ALLOW_FORCE_DELETE=0

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_GREEN=$'\033[32m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_OFF=$'\033[0m'
else
  C_RED='' C_YELLOW='' C_GREEN='' C_DIM='' C_BOLD='' C_OFF=''
fi

say() {
  [ "$ORIGIN_QUIET" = 1 ] || printf '%s\n' "$*" >&2
}

note() {
  [ "$ORIGIN_QUIET" = 1 ] || printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF" >&2
}

good() {
  [ "$ORIGIN_QUIET" = 1 ] || printf '%s%s%s\n' "$C_GREEN" "$*" "$C_OFF" >&2
}

warn() {
  printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2
}

debug() {
  [ "$ORIGIN_VERBOSE" = 1 ] && printf '%s+ %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2
  return 0
}

die() {
  printf '%sorigin:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2
  exit 1
}

# A blank line, suppressed with the rest of the chatter.
blank() {
  [ "$ORIGIN_QUIET" = 1 ] || printf '\n' >&2
}

require_cmd() {
  local cmd="$1" hint="${2:-}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  die "${cmd} is not installed${hint:+; ${hint}}"
}

# Refuses a flag that takes a value and was given none.
#
# Called as `require_value --path "${@:2}"` - everything after the flag, which
# is empty when the flag was the last argument. Reading `$2` directly instead
# is a bash `unbound variable` crash under `set -u`, with no origin: prefix and
# nothing saying which flag was short.
require_value() {
  local flag="$1"
  shift
  [ "$#" -gt 0 ] || die "${flag} needs a value"
}

# Renders a command the way a person would have to type it, so a dry run and a
# confirmation prompt show something that can be pasted.
quote_args() {
  local out='' arg
  for arg in "$@"; do
    case "$arg" in
      *[!A-Za-z0-9_./:=@-]* | '')
        out="${out}'$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")' "
        ;;
      *) out="${out}${arg} " ;;
    esac
  done
  printf '%s' "${out% }"
}

# Runs a command, unless this is a dry run, in which case it says what it would
# have run and reports success.
#
# Named `origin_run` rather than `run` because bats defines a `run` of its own,
# and a test file that sources this would otherwise silently replace it.
#
# Its stdout goes to stderr. `git worktree add` announces itself there, `gh pr
# merge` prints a URL, and `cd "$(origin wt add foo)"` breaks the moment either
# of them lands on stdout beside the path. Nothing run through here produces
# output anybody parses.
origin_run() {
  if [ "$ORIGIN_DRY_RUN" = 1 ]; then
    printf '%swould run:%s %s\n' "$C_DIM" "$C_OFF" "$(quote_args "$@")" >&2
    return 0
  fi
  debug "$(quote_args "$@")"
  "$@" >&2
}

# Every git invocation that changes something. Read-only git is called
# directly, because a guard that also has to allow `git log` teaches nobody
# anything.
git_run() {
  git_guard "$@"
  origin_run git "$@"
}

# The arguments this plugin never passes, checked at the one place they would
# have to pass through.
#
# These are not hypothetical: `reset --hard` and `clean -fdx` are what an agent
# reaches for when it has misread the situation, and a bare `--force` is how a
# rebase that went wrong becomes a colleague's lost afternoon.
#
# Every refusal here is absolute. No flag reaches this function, `--yes` least
# of all: these are the commands whose whole purpose is to destroy something
# git cannot give back, so there is nothing for a confirmation to be about.
# Where a user genuinely wants one, the message says so and they type it.
git_guard() {
  local subcommand arg delete=0 force=0 letters

  # Global options come before the subcommand, and several take a value.
  # Skipping them is what makes `git_run -C <path> branch -D x` reach the
  # branch guard below rather than sliding past it as a subcommand named `-C`.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C | -c | --git-dir | --work-tree | --namespace | --exec-path | --super-prefix)
        shift
        shift || true
        ;;
      --git-dir=* | --work-tree=* | --namespace=* | --exec-path=* | --config-env=*)
        shift
        ;;
      -p | -P | --paginate | --no-pager | --bare | --no-replace-objects)
        shift
        ;;
      --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | --icase-pathspecs)
        shift
        ;;
      *) break ;;
    esac
  done

  # A leading dash here is a global this does not know, and the token after it
  # would be read as the subcommand - which is how a guard stops guarding. Every
  # call site is this plugin's own, so refusing is a bug report, not a
  # limitation somebody hits.
  case "${1:-}" in
    -*) die "refusing a git command whose subcommand cannot be identified: $(quote_args "$@")" ;;
  esac

  subcommand="${1:-}"
  shift || true
  case "$subcommand" in
    reset)
      for arg in "$@"; do
        case "$arg" in
          --hard)
            die "refusing to run 'git reset --hard'; this plugin never discards work"
            ;;
        esac
      done
      ;;
    clean)
      for arg in "$@"; do
        case "$arg" in
          -f | --force | -[a-eg-z]*f* | -f*)
            die "refusing to run 'git clean' with --force; this plugin never deletes untracked files"
            ;;
        esac
      done
      ;;
    push)
      for arg in "$@"; do
        case "$arg" in
          -f | --force)
            die "refusing a bare --force; use --force-with-lease --force-if-includes"
            ;;
        esac
      done
      ;;
    branch)
      # `-D`, `-d -f`, `-df` and `--delete --force` are one command with four
      # spellings, and a guard that knows only the first is decoration.
      for arg in "$@"; do
        case "$arg" in
          --) break ;;
          --delete) delete=1 ;;
          --force) force=1 ;;
          --*) ;;
          -*)
            letters="${arg#-}"
            case "$letters" in *[dD]*) delete=1 ;; esac
            case "$letters" in *[Df]*) force=1 ;; esac
            ;;
        esac
      done
      if [ "$delete" = 1 ] && [ "$force" = 1 ]; then
        [ "$ORIGIN_ALLOW_FORCE_DELETE" = 1 ] ||
          die "refusing to force-delete a branch without an explicit --force on a branch proven merged"
      fi
      ;;
    worktree)
      # No exception, and no variable that could grant one: the only worktree
      # this plugin removes is one it has just found clean, and git refuses
      # that one without --force anyway. Reaching here means the checkout holds
      # something, and that is the user's to deal with.
      for arg in "$@"; do
        case "$arg" in
          -f | --force)
            die "refusing 'git worktree remove --force'; a worktree with work in it is left alone, not removed"
            ;;
        esac
      done
      ;;
  esac
}

# The only way this plugin pushes over a branch somebody else may have moved.
# --force-if-includes is not decoration beside --force-with-lease. The lease
# alone compares the remote against this clone's remote-tracking ref, and a
# `git fetch` updates that ref - so after a fetch the lease passes and somebody
# else's commits are overwritten. --force-if-includes additionally requires
# that the ref being replaced be reachable from this branch's reflog: that this
# clone actually had those commits and built on them. Together they tell a
# branch this clone rebased from a branch somebody else pushed.
#
# --set-upstream because a branch pushed by hand without it still has a
# remote-tracking ref, and the next push should not have to work that out
# again.
#
# `refs/heads/<branch>` because a bare name is a refspec git resolves against
# every namespace: beside a tag of the same name it matches both and the push
# is refused outright.
git_push_lease() {
  local remote="$1" branch="$2"
  git_run push --force-with-lease --force-if-includes --set-upstream "$remote" "refs/heads/${branch}"
}

# Can this process actually open a terminal?
#
# Not `[ -r /dev/tty ]`: on macOS that device exists and passes the test even
# when there is no controlling terminal, and the failure then arrives as
# "Device not configured" from inside whatever tried to read it.
have_tty() {
  { : </dev/tty; } 2>/dev/null
}

# What will not be there afterwards, named before anything asks about it.
#
# The commands in a confirmation say what will run. This says what goes: the
# path, the files, the branch and the sha, each with the command that brings it
# back. Nobody can weigh `git worktree remove <path>` without being told that
# the path holds a `.env` nothing tracks.
#
# Printed whatever the flags say. --quiet silences commentary and --yes answers
# questions; neither is a reason to delete something without saying so, and the
# lines are the record of what went afterwards.
losing() {
  local heading="$1"
  shift
  [ "$#" -gt 0 ] || return 0
  printf '\n%s%s%s\n' "$C_BOLD" "$heading" "$C_OFF" >&2
  printf '  %s\n' "$@" >&2
}

# Asks, having first printed the exact commands that will run.
#
# Under --yes it returns without reading anything, so an agent invocation can
# never hang on a prompt nobody is there to answer. Without --yes and without a
# terminal it refuses rather than assuming consent.
#
# Everything this answers for is recoverable: a deleted branch prints the
# command that restores it, a rewritten branch is in the reflog, a merge is on
# the forge. For anything else, see `confirm_unrecoverable`.
confirm() {
  local prompt="$1" reply
  shift
  if [ "$ORIGIN_ASSUME_YES" = 1 ] || [ "$ORIGIN_DRY_RUN" = 1 ]; then
    return 0
  fi
  if [ "$#" -gt 0 ]; then
    printf '\n%sThis will run:%s\n' "$C_BOLD" "$C_OFF" >&2
    printf '  %s\n' "$@" >&2
    printf '\n' >&2
  fi
  if ! have_tty; then
    die "${prompt}: refusing to continue without a terminal to ask; pass --yes"
  fi
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply </dev/tty || reply=''
  case "$reply" in
    y | Y | yes | Yes | YES) return 0 ;;
    *) die "aborted" ;;
  esac
}

# A confirmation that --yes cannot give.
#
# For the one class of loss that has no undo: content git never tracked. There
# is no sha to print and no ref to restore, so an answer nobody was asked for
# is not an answer. --yes means "do not stop to ask me about the ordinary
# steps"; it has never meant "and lose whatever is not in git".
#
# The way through is the flag named in `escape`, typed deliberately, or a
# person at a terminal saying yes to a list of what goes.
confirm_unrecoverable() {
  local prompt="$1" escape="$2" reply
  if [ "$ORIGIN_DRY_RUN" = 1 ]; then
    note "would ask: ${prompt}"
    return 0
  fi
  if [ "$ORIGIN_ASSUME_YES" = 1 ]; then
    die "${prompt} --yes does not answer that, because nothing can put it back; pass ${escape} if you mean it"
  fi
  if ! have_tty; then
    die "${prompt} there is no terminal to ask at; pass ${escape} if you mean it"
  fi
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply </dev/tty || reply=''
  case "$reply" in
    y | Y | yes | Yes | YES) return 0 ;;
    *) die "aborted" ;;
  esac
}

# JSON, without requiring jq to produce it.
#
# jq is needed to read what gh and glab return, so the forge commands ask for
# it. The git-only commands do not, and `wt list --json` on a plane is worth
# the twenty lines.
json_string() {
  printf '"'
  printf '%s' "${1-}" |
    LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' |
    awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
  printf '"'
}

json_field() {
  printf '%s:%s' "$(json_string "$1")" "$(json_string "${2-}")"
}

json_raw_field() {
  printf '%s:%s' "$(json_string "$1")" "${2-null}"
}

json_bool() {
  case "${1-}" in
    1 | true | yes) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# Reads one string out of a JSON object without a JSON parser, for the two
# places that have a manifest and no jq: `origin --version` and nothing else.
json_peek() {
  local file="$1" key="$2"
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" |
    head -1
}

origin_version() {
  local manifest="${ORIGIN_ROOT}/.claude-plugin/plugin.json"
  if [ -r "$manifest" ]; then
    json_peek "$manifest" version
  else
    printf 'unknown'
  fi
}

# Flag parsing shared by every subcommand.
#
# `--json` is not here. `git-worktree list` is the only subcommand with
# machine-readable output, so it parses that flag itself; a flag every
# subcommand accepts and then ignores reads as support for something nobody
# wrote.
#
# shellcheck disable=SC2034  # these are read by the subcommand files that source this one
parse_common_flag() {
  case "$1" in
    --dry-run) ORIGIN_DRY_RUN=1 ;;
    --no-dry-run) ORIGIN_DRY_RUN=0 ;;
    -y | --yes) ORIGIN_ASSUME_YES=1 ;;
    -q | --quiet) ORIGIN_QUIET=1 ;;
    -v | --verbose) ORIGIN_VERBOSE=1 ;;
    --no-color) C_RED='' C_YELLOW='' C_GREEN='' C_DIM='' C_BOLD='' C_OFF='' ;;
    *) return 1 ;;
  esac
  return 0
}

# Aligns tab-separated rows into columns, reading them from stdin.
#
# `column -t` collapses an empty field, which in a table where a column is
# sometimes empty silently shifts every value after it one place to the left.
tabulate() {
  awk -F'\t' '
    {
      rows[NR] = $0
      for (i = 1; i <= NF; i++) {
        if (length($i) > width[i]) width[i] = length($i)
      }
      if (NF > columns) columns = NF
    }
    END {
      for (r = 1; r <= NR; r++) {
        split(rows[r], field, "\t")
        line = ""
        for (i = 1; i <= columns; i++) {
          line = line sprintf("%-*s", (i < columns ? width[i] + 2 : 0), field[i])
        }
        sub(/[ ]+$/, "", line)
        print line
      }
    }
  ' >&2
}

# One indented line per line of input, on stderr, skipping blanks.
#
# Not `printf '  %s\n' $list`: that splits on spaces too, and a conflicted path
# with a space in it would be reported as two files that do not exist.
indent_lines() {
  local prefix="${1:-  }" line
  while IFS= read -r line; do
    # A blank line stays blank rather than picking up trailing whitespace, and
    # is not dropped: in a merge body it is the paragraph break.
    if [ -z "$line" ]; then
      printf '\n' >&2
    else
      printf '%s%s\n' "$prefix" "$line" >&2
    fi
  done
}

# A JSON array of strings, one per line of input, blanks dropped.
json_array_from_lines() {
  local line first=1
  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    json_string "$line"
  done
  printf ']'
}

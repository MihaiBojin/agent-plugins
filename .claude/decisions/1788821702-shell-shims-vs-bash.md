# Where the implementation lives: bash executable or shell functions

Topic: origin, the zsh git-worktree plugin and the fish one implement the same idea, and which of them is the implementation keeps coming back
Status: decided 2026-09-08
Opened: 2026-09-07

## 2026-09-07

q: Can the logic move into zsh and fish functions, leaving a few bash helpers for the agent?
a: No. The bash executable stays the implementation; shell shims call it
why: the agent's shell is zsh restored from ~/.claude/shell-snapshots, which keeps the autoload stubs and drops fpath, so `gwl` resolves as a function and then fails with "function definition file not found", while `command -v origin` resolves
alt: vendor a copy of bin/origin into shell-plugins — a fourth copy of the same logic
alt: point the shim at the installed plugin — ~/.claude/plugins/cache/MihaiBojin/origin/0.10.0 is version-numbered and moves on every update; the marketplace clone at ~/.claude/plugins/marketplaces/MihaiBojin is not

q: Do the zsh and fish worktree implementations become shims to origin?
a: Not yet. origin has no completions and no branch picker, and those are the two things the shell versions give that a shim would drop
why: 1201 lines of bash, 2501 of zsh and 1768 of fish say the same thing three times, and only completions stand between here and deleting two of them

## 2026-09-08

q: Is the previous answer right that an agent cannot reach a shell function?
a: No. `fish -c 'gwl'` runs it and prints the list; `zsh -ic 'gwl'` runs it too
why: the earlier test called the function from the agent's own zsh, which is restored from a snapshot with no fpath; going through the shell's own startup loads it normally
alt: none - the test replaced the claim

q: Which side holds the worktree logic?
a: the zsh and fish gw* functions; origin keeps merge, renew and the bash helpers only an agent needs
why: it is the terminal's tool first, and the shells already carry a fuller implementation than the bash one
alt: shims to bin/origin, deleting 4269 lines of shell - rejected: it would take the completions and the pickers with them

# Model routing

The coordinator owns the run record, mutation order, and final merge. Delegate
bounded tasks with explicit model selection when the client exposes it.
A skill instruction does not itself switch the active model, and a worker must report which model
actually ran. Do not change the user's global model configuration.

| Work                                                                              | Model                                                            |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Inspect status, choose the next recorded step, stage known paths, publish, poll   | Fast general-purpose model                                       |
| Fetch failed jobs and log excerpts, identify the current head and run IDs         | Fast general-purpose model                                       |
| Diagnose or edit code/tests; resolve rebase, cherry-pick, or stash conflicts      | Most capable available model, highest supported reasoning effort |
| Routine operation still failing after three attempted remedies for the same cause | Most capable available model                                     |

In Claude Code, use the Agent tool's `model: sonnet` for routine work and
`model: opus` for reasoning and code work, subject to the installed client's
available models and organization policy. Keep orchestration in the main
conversation: subagents may not be able to create further subagents. If a fast
worker finds code work, it returns its evidence for a new strong worker.

In Codex, select from the model identifiers and descriptions actually exposed
by the host's agent tool. Use its fast coding/general-purpose option for
routine work and its most capable reasoning/coding option for code and
conflicts. Supply the tool's supported model and reasoning-effort arguments;
do not invent an `opus` alias or assume Claude's frontmatter selects a Codex
model. If discovery is needed, use the installed client's model catalog
(`codex debug models` when available). Model names and supported effort levels
come from that catalog, not from version numbers guessed by the skill.

If the current model is already the required class, it can do the task
directly. If the host cannot route models, disclose that limitation. Continue
routine work with the current model, but hand back before code/conflict work
when the required stronger model is unavailable. Never claim a model switch
that the host did not perform.

Give each worker the scoped files, base/head SHAs, evidence and relevant
repository instructions. Request changed paths, the diagnosis, tests run,
and remaining uncertainty. Code/conflict workers return edits and validation;
they do not commit or publish. After validating that result, the coordinator
can assign a fast worker exact staging, commit, push, or PR-creation commands
with the verified source, target, and expected SHA. Recheck those facts before
execution. Workers must not spawn more workers, expand scope, merge, or reply
to reviewers. Only one worker may mutate the checkout or remote at a time;
log collectors remain read-only.

An attempt is a remedy followed by verification, not a status poll. Count
attempts by cause across pushes and worker replacements. For code/conflicts,
start strong on the first attempt. After three unsuccessful strong-model
remedies for the same cause, stop that repair and report the missing decision
or evidence. Repeating the same patch or weakening a test is not progress.

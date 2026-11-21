---
tags: [e2e]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Turn these notes into a runbook. Reply with only the document, in Markdown.

how to rotate the signing key for `billing-api`. do it when the `signing-key-age` alert fires. you need the `secrets-admin` role.

make the new key with `keyctl new billing-api`, it prints the key id. then roll it out, `deployctl rollout billing-api --key KEY_ID`, and wait till `deployctl status billing-api` says `healthy`. then delete the old key with `keyctl delete billing-api --old`. careful, after that every token signed with the old key stops working and you cant undo it, so only do it once status is healthy. if status isnt healthy after 10 min, page `platform-oncall` and dont delete anything.

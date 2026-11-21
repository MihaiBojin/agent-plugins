---
type: llm
weight: 1
---

Rule `notes_not_steps`: a note carries background only.

Pass if the document has no note. Also pass if every note holds background only, so that the procedure still works with every note deleted.

Fail if a note holds an action, a limit or a risk. Quote the note that decides it.

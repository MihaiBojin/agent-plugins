# Set these on the command line: make run CLAUDE_MODEL=sonnet CODEX_MODEL=
# An empty model skips that client. Plain `=` keeps a CLAUDE_EFFORT or similar in
# the shell environment from changing a run; values on the command line still win.
PYTHON ?= python3
CLAUDE_MODEL = haiku
CLAUDE_EFFORT =
CODEX_MODEL = gpt-6-luna
CODEX_EFFORT = low
JOBS = 4
# Anything else for testbed.py, such as ARGS='--suite threads --repeat 3'.
ARGS =
# A run directory for `make report`. Defaults to the latest run.
RUN = out/latest-run
WORK ?= $(shell $(PYTHON) -c 'import os, tempfile; print(os.environ.get("DIALOGUE_TESTBED_WORK") or os.path.join(tempfile.gettempdir(), "dialogue-testbed"))')

AGENTS = $(if $(CLAUDE_MODEL),--agent claude:$(CLAUDE_MODEL)$(if $(CLAUDE_EFFORT),:$(CLAUDE_EFFORT))) \
	$(if $(CODEX_MODEL),--agent codex:$(CODEX_MODEL)$(if $(CODEX_EFFORT),:$(CODEX_EFFORT)))

.PHONY: render plan run plan-full run-full report test clean

render:
	$(PYTHON) testbed.py render $(ARGS)

plan:
	$(PYTHON) testbed.py plan $(AGENTS) --jobs $(JOBS) $(ARGS)

run:
	$(PYTHON) testbed.py run $(AGENTS) --jobs $(JOBS) --work "$(WORK)" $(ARGS)

plan-full:
	$(PYTHON) testbed.py plan --full $(AGENTS) --jobs $(JOBS) $(ARGS)

run-full:
	$(PYTHON) testbed.py run --full $(AGENTS) --jobs $(JOBS) --work "$(WORK)" $(ARGS)

report:
	$(PYTHON) testbed.py report "$(RUN)"

test:
	$(PYTHON) -B -m unittest discover -s tests -v

# Every run and render under out/, and the scratch space an interrupted run left behind.
clean:
	rm -rf out
	rm -rf "$(WORK)"

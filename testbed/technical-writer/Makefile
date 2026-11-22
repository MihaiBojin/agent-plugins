# Set these on the command line: make run CLAUDE_MODEL=sonnet CODEX_MODEL=
# An empty model skips that client. Plain `=` keeps a CLAUDE_EFFORT or similar in
# the shell environment from changing a run; values on the command line still win.
PYTHON ?= python3
CLAUDE_MODEL = haiku
CLAUDE_EFFORT =
CODEX_MODEL = gpt-6-luna
CODEX_EFFORT = low
JOBS = 6
REPEAT = 6
# Anything else for bench.py, such as ARGS='--task runbook --config full'.
ARGS =
# A run directory for `make report`. Defaults to the latest run.
RUN = out/latest-run
# The model that grades every document against every rule.
JUDGE = claude:sonnet
WORK ?= $(shell $(PYTHON) -c 'import os, tempfile; print(os.environ.get("TECHNICAL_WRITER_BENCH_WORK") or os.path.join(tempfile.gettempdir(), "technical-writer-bench"))')

AGENTS = $(if $(CLAUDE_MODEL),--agent claude:$(CLAUDE_MODEL)$(if $(CLAUDE_EFFORT),:$(CLAUDE_EFFORT))) \
	$(if $(CODEX_MODEL),--agent codex:$(CODEX_MODEL)$(if $(CODEX_EFFORT),:$(CODEX_EFFORT)))

.PHONY: plan run plan-rules run-rules report test clean

plan:
	$(PYTHON) -B bench.py plan $(AGENTS) --judge $(JUDGE) --repeat $(REPEAT) $(ARGS)

# Every group of rules removed in turn, and the plugin off and on. Asks before it starts.
run:
	$(PYTHON) -B bench.py run $(AGENTS) --judge $(JUDGE) --repeat $(REPEAT) --jobs $(JOBS) --work "$(WORK)" $(ARGS)

plan-rules:
	$(PYTHON) -B bench.py plan --units rules $(AGENTS) --judge $(JUDGE) --repeat $(REPEAT) $(ARGS)

# Every rule removed in turn: about three times the sessions of run.
run-rules:
	$(PYTHON) -B bench.py run --units rules $(AGENTS) --judge $(JUDGE) --repeat $(REPEAT) --jobs $(JOBS) \
		--work "$(WORK)" $(ARGS)

report:
	$(PYTHON) -B bench.py report "$(RUN)"

test:
	$(PYTHON) -B -m unittest discover -s tests -v

clean:
	rm -rf out "$(WORK)"

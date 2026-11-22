# Set these on the command line: make e2e PLUGIN=technical-writing CODEX_MODEL=
# An empty model skips that client. Plain `=` keeps a variable in the shell
# environment from changing a run; values on the command line still win.
PYTHON ?= python3
PLUGIN = technical-writing
PLUGIN_DIR = plugins/$(PLUGIN)
CLAUDE_MODEL = fable
CODEX_MODEL = gpt-6-astra

.PHONY: e2e benchmark

# Runs every eval case of the plugin that is tagged e2e, with both clients.
# Each run spends tokens on the Claude account and on the Codex account.
e2e:
	$(PYTHON) -B testbed/e2e/e2e.py "$(PLUGIN_DIR)" \
		$(if $(CLAUDE_MODEL),--claude $(CLAUDE_MODEL)) $(if $(CODEX_MODEL),--codex $(CODEX_MODEL))

# Runs the plugin's benchmark in testbed/$(PLUGIN), which asks before it starts.
# Pass its settings through, such as make benchmark ARGS='--task runbook'.
benchmark:
	$(MAKE) -C testbed/$(PLUGIN) run

"""Run each e2e case of one plugin with Claude Code and with Codex, and report which checks passed.

An e2e case is an eval case tagged `e2e`: `<plugin>/evals/e2e-<skill>/`, with a `prompt.md`
and graders that cost nothing to run. Claude Code runs the cases itself, through
`claude plugin eval`. Codex has no such command, so this script installs the plugin into a
throwaway CODEX_HOME, sends each prompt through `codex exec`, and applies the same `regex`
graders to the reply.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TAG = 'e2e'
TIMEOUT_SECONDS = 600

# Variables an agent session sets for its own child processes. A run started from inside
# Claude Code or Codex would otherwise pass on that session's effort and session ID.
SESSION_VARIABLES = ('CLAUDECODE', 'CLAUDE_EFFORT', 'CLAUDE_PID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SESSION_ID',
                     'CLAUDE_CODE_CHILD_SESSION', 'CLAUDE_CODE_SESSION_ATTENDED', 'CLAUDE_CODE_MESSAGING_SOCKET',
                     'CLAUDE_CODE_MESSAGING_TOKEN', 'CLAUDE_CODE_BRIDGE_SESSION_ID', 'CLAUDE_CODE_EXECPATH',
                     'CLAUDE_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_SANDBOX', 'CODEX_SANDBOX_NETWORK_DISABLED')


def clean_env(**extra):
    env = {key: value for key, value in os.environ.items() if key not in SESSION_VARIABLES}
    return {**env, **extra}


def scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] == "'":
        return text[1:-1].replace("''", "'")
    if len(text) >= 2 and text[0] == text[-1] == '"':
        return json.loads(text)
    if text.startswith('[') and text.endswith(']'):
        return [scalar(item) for item in text[1:-1].split(',') if item.strip()]
    return text


def front_matter(text):
    """The `key: value` lines between the two `---` lines, and the text after them."""
    match = re.match(r'---\n(.*?)\n---\n?(.*)', text, re.S)
    if not match:
        return {}, text
    fields = {}
    for line in match.group(1).splitlines():
        key, separator, value = line.partition(':')
        if separator and key.strip() and not line.startswith((' ', '#')):
            fields[key.strip()] = scalar(value)
    return fields, match.group(2).strip()


def load_cases(plugin):
    """Every eval case of the plugin that is tagged e2e, with its prompt and its regex graders."""
    cases = []
    for prompt_file in sorted(Path(plugin).glob('evals/*/prompt.md')):
        fields, prompt = front_matter(prompt_file.read_text(encoding='utf-8'))
        if TAG not in (fields.get('tags') or []):
            continue
        graders = []
        for grader_file in sorted(prompt_file.parent.glob('graders/*.md')):
            grader, _ = front_matter(grader_file.read_text(encoding='utf-8'))
            if grader.get('type') == 'regex':
                graders.append({'name': grader_file.stem, **grader})
        name = prompt_file.parent.name
        cases.append({'name': name, 'skill': name.removeprefix('e2e-'), 'prompt': prompt, 'graders': graders})
    return cases


def regex_passes(grader, text):
    """A `regex` grader as `claude plugin eval` reads it: found, `not_contains`, or `count:N`."""
    flags = re.IGNORECASE if 'i' in grader.get('flags', '') else 0
    found = len(re.findall(grader['pattern'], text, flags))
    match = grader.get('match', '')
    if match == 'not_contains':
        return found == 0
    if match.startswith('count:'):
        return found == int(match.removeprefix('count:'))
    return found > 0


def run(command, **options):
    return subprocess.run(command, capture_output=True, text=True, stdin=subprocess.DEVNULL, **options)


def claude_reply(lines):
    """The reply in a `claude plugin eval` trace: the result of its last result event."""
    reply = ''
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict) and event.get('type') == 'result':
            reply = event.get('result') or ''
    return reply


def delete_sealed(folder):
    """Delete a directory tree whose directories the eval left without write or read permission."""
    folder.chmod(0o700)
    for entry in folder.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            delete_sealed(entry)
        else:
            entry.unlink()
    folder.rmdir()


def keep_claude_trace(trace, to):
    """Copy one run's trace and reply to `to`, then delete the scaffold directory `--keep-temp` left."""
    trace = Path(trace or '')
    if trace.name != 'trace.jsonl' or not trace.is_file():
        return
    to.mkdir(parents=True, exist_ok=True)
    text = trace.read_text(encoding='utf-8')
    (to / 'events.jsonl').write_text(text, encoding='utf-8')
    (to / 'reply.md').write_text(claude_reply(text.splitlines()), encoding='utf-8')
    if trace.parent.name == 'out':
        delete_sealed(trace.parent.parent)


def run_claude(plugin, model, out):
    """One `claude plugin eval` over the tagged cases. Returns the rows and a line on what it cost.

    The eval keeps no reply, only a trace in a scaffold directory that it deletes, so `--keep-temp` holds it."""
    result_file = out / 'claude.json'
    command = ['claude', 'plugin', 'eval', str(plugin), '--tag', TAG, '--ablation', 'none', '--runs', '1',
               '--concurrency', '4', '--model', model, '--no-publish', '--trust-plugin', '--keep-temp',
               '--output-dir', str(out / 'claude'), '--json', str(result_file)]
    done = run(command, env=clean_env(), timeout=TIMEOUT_SECONDS * 2)
    (out / 'claude.log').write_text(done.stdout + done.stderr, encoding='utf-8')
    if not result_file.exists():
        return [('claude', '-', 'claude plugin eval', False)], f'claude: no result, see {out / "claude.log"}'
    result = json.loads(result_file.read_text(encoding='utf-8'))
    rows = []
    for case in result['cases']:
        for attempt in case['arms']['with']:
            keep_claude_trace(attempt.get('tracePath'), out / 'claude' / case['name'])
            if attempt.get('error'):
                rows.append(('claude', case['name'], 'run', False))
            for grader in attempt['graders']:
                rows.append(('claude', case['name'], grader['name'], bool(grader['passed'])))
    return rows, f'claude ({model}): ${result["costUsd"]:.2f} at list price, {result["durationSeconds"]}s'


class CodexHome:
    """A throwaway CODEX_HOME that holds the user's login, the plugin under test and nothing else."""

    def __init__(self, root, plugin):
        self.name = json.loads((plugin / '.codex-plugin' / 'plugin.json').read_text(encoding='utf-8'))['name']
        self.path = root / 'codex-home'
        self.path.mkdir(parents=True)
        login = Path(os.environ.get('CODEX_HOME', '~/.codex')).expanduser() / 'auth.json'
        if not login.exists():
            raise RuntimeError(f'no Codex login at {login}; run `codex login` first')
        (self.path / 'auth.json').symlink_to(login)
        marketplace = root / 'marketplace'
        shutil.copytree(plugin, marketplace / 'plugins' / self.name,
                        ignore=shutil.ignore_patterns('__pycache__', '.DS_Store', 'results'))
        (marketplace / '.agents' / 'plugins').mkdir(parents=True)
        (marketplace / '.agents' / 'plugins' / 'marketplace.json').write_text(json.dumps({
            'name': 'testbed', 'interface': {'displayName': 'testbed'},
            'plugins': [{'name': self.name, 'source': {'source': 'local', 'path': f'./plugins/{self.name}'},
                         'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
                         'category': 'Developer Tools'}]}, indent=2), encoding='utf-8')
        for arguments in (['plugin', 'marketplace', 'add', str(marketplace)],
                          ['plugin', 'add', f'{self.name}@testbed']):
            done = run(['codex', *arguments], env=self.env())
            if done.returncode != 0:
                raise RuntimeError(f'codex {" ".join(arguments)} failed: {done.stderr.strip()}')
        with open(self.path / 'config.toml', 'a', encoding='utf-8') as config:
            # Plugins from the account would add context that the test did not ask for.
            config.write('\n[features]\nremote_plugin = false\n')

    def env(self):
        return clean_env(CODEX_HOME=str(self.path))


def parse_codex(lines):
    """One `codex exec --json` run: the reply, every command it ran, its token usage and its error."""
    reply, commands, usage, error = '', [], {}, None
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        item = event.get('item') or {}
        if event.get('type') == 'item.completed' and item.get('type') == 'agent_message':
            reply = item.get('text') or reply
        elif event.get('type') == 'item.completed' and item.get('type') == 'command_execution':
            commands.append(item.get('command') or '')
        elif event.get('type') == 'turn.completed':
            usage = event.get('usage') or {}
        elif event.get('type') in ('turn.failed', 'error'):
            error = (event.get('error') or {}).get('message') or event.get('message') or event['type']
    return {'reply': reply, 'commands': commands, 'usage': usage, 'error': error}


def skill_was_read(commands, skill):
    """Codex loads a skill by reading its SKILL.md in a shell command."""
    return any(f'skills/{skill}/SKILL.md' in command for command in commands)


def run_codex_case(case, home, model, out):
    workspace = out / 'codex' / case['name']
    workspace.mkdir(parents=True)
    command = ['codex', 'exec', '--json', '--skip-git-repo-check', '--sandbox', 'read-only', '-m', model,
               '--', case['prompt']]
    try:
        done = run(command, cwd=workspace, env=home.env(), timeout=TIMEOUT_SECONDS)
        stdout, failure = done.stdout, f'codex exited with {done.returncode}' if done.returncode else None
    except subprocess.TimeoutExpired as expired:
        stdout = expired.stdout.decode() if isinstance(expired.stdout, bytes) else expired.stdout or ''
        failure = f'timed out after {TIMEOUT_SECONDS}s'
    (workspace / 'events.jsonl').write_text(stdout, encoding='utf-8')
    turn = parse_codex(stdout.splitlines())
    (workspace / 'reply.md').write_text(turn['reply'], encoding='utf-8')
    rows = []
    if turn['error'] or failure:
        rows.append(('codex', case['name'], f'run: {turn["error"] or failure}', False))
    rows.append(('codex', case['name'], 'skill_fired', skill_was_read(turn['commands'], case['skill'])))
    for grader in case['graders']:
        rows.append(('codex', case['name'], grader['name'], regex_passes(grader, turn['reply'])))
    return rows, turn['usage']


def run_codex(plugin, model, cases, out):
    """Each case through `codex exec`. Returns the rows and a line on the tokens it used."""
    try:
        home = CodexHome(out / 'codex-setup', plugin)
    except RuntimeError as error:
        return [('codex', '-', f'setup: {error}', False)], 'codex: setup failed'
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda case: run_codex_case(case, home, model, out), cases))
    rows = [row for case_rows, _ in results for row in case_rows]
    total = {key: sum(usage.get(key, 0) for _, usage in results)
             for key in ('input_tokens', 'cached_input_tokens', 'output_tokens')}
    return rows, (f'codex ({model}): {total["input_tokens"]:,} input tokens, '
                  f'{total["cached_input_tokens"]:,} of them cached, {total["output_tokens"]:,} output tokens')


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('plugin', type=Path, help='the plugin directory, such as plugins/technical-writing')
    parser.add_argument('--claude', metavar='MODEL', help='run the cases with Claude Code on this model')
    parser.add_argument('--codex', metavar='MODEL', help='run the cases with Codex on this model')
    parser.add_argument('--out', type=Path, default=HERE / 'out', help='where each run keeps its replies')
    options = parser.parse_args(arguments)

    plugin = options.plugin.resolve()
    cases = load_cases(plugin)
    if not cases:
        print(f'{options.plugin} has no eval case tagged {TAG}: nothing to run')
        return 0
    clients = [client for client in ('claude', 'codex') if getattr(options, client)]
    missing = [client for client in clients if shutil.which(client) is None]
    if missing or not clients:
        print(f'not on PATH: {", ".join(missing)}' if missing else 'name a model with --claude or --codex')
        return 2

    out = options.out / datetime.now().strftime('%Y%m%d-%H%M%S')
    out.mkdir(parents=True)
    print(f'{len(cases)} cases of {options.plugin}, with {" and ".join(clients)}: {", ".join(c["name"] for c in cases)}')
    with tempfile.TemporaryDirectory(prefix='e2e-') as scratch, ThreadPoolExecutor(max_workers=2) as pool:
        futures = []
        if options.claude:
            futures.append(pool.submit(run_claude, plugin, options.claude, out))
        if options.codex:
            futures.append(pool.submit(run_codex, plugin, options.codex, cases, Path(scratch)))
        results = [future.result() for future in futures]
        if options.codex and (Path(scratch) / 'codex').is_dir():
            shutil.copytree(Path(scratch) / 'codex', out / 'codex')

    failed = 0
    for rows, _ in results:
        for client, case, check, passed in rows:
            failed += not passed
            print(f'{"pass" if passed else "FAIL"}  {client:6}  {case:24}  {check}')
    for _, spent in results:
        print(spent)
    print(f'{failed} failed. Replies are in {out}' if failed else f'All passed. Replies are in {out}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

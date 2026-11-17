"""Drive claude -p and codex exec through one scripted conversation, a turn at a time.

Claude keeps one process for the whole conversation (stream-json input), so its
SessionStart hook runs once. Codex has no such mode: every turn after the first
is a new `codex exec resume`, and its SessionStart hook runs again each time.
"""

import json
import os
from pathlib import Path
import queue
import shlex
import shutil
import subprocess
import threading
import time
import uuid

OUTPUT_LIMIT = 4000

# Variables an agent session sets for its own child processes. A testbed started
# from inside Claude Code or Codex would otherwise pass on that session's effort,
# session ID and messaging socket. Login variables are kept.
SESSION_VARIABLES = ('CLAUDECODE', 'CLAUDE_EFFORT', 'CLAUDE_PID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SESSION_ID',
                     'CLAUDE_CODE_CHILD_SESSION', 'CLAUDE_CODE_SESSION_ATTENDED', 'CLAUDE_CODE_MESSAGING_SOCKET',
                     'CLAUDE_CODE_MESSAGING_TOKEN', 'CLAUDE_CODE_BRIDGE_SESSION_ID', 'CLAUDE_CODE_EXECPATH',
                     'CLAUDE_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_SANDBOX', 'CODEX_SANDBOX_NETWORK_DISABLED')


def clean_env(**extra):
    env = {key: value for key, value in os.environ.items() if key not in SESSION_VARIABLES}
    return {**env, **extra}


def clip(text, limit=OUTPUT_LIMIT):
    text = text if isinstance(text, str) else json.dumps(text, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + f'\n... [{len(text) - limit} more characters]'


def claude_allowed_tools(plugin):
    """Read the workspace, edit it, run the dialogue tool, the tests and read-only git; nothing else."""
    return ['Read', 'Glob', 'Grep', 'Edit', 'Write', f'Bash({plugin}/bin/dialogue *)',
            'Bash(python3 -m unittest*)', 'Bash(git diff*)', 'Bash(git status*)', 'Bash(ls*)']


def tool_result_text(content):
    if isinstance(content, list):
        return '\n'.join(part.get('text', '') for part in content if isinstance(part, dict))
    return content if isinstance(content, str) else json.dumps(content)


def parse_claude_turn(events):
    """One turn's stream-json events as text, tool calls, the reply, usage and cost."""
    items, calls, result = [], {}, {}
    for event in events:
        kind = event.get('type')
        if kind == 'assistant':
            for block in event.get('message', {}).get('content', []):
                if block.get('type') == 'text' and block.get('text', '').strip():
                    items.append({'type': 'text', 'text': block['text']})
                elif block.get('type') == 'tool_use':
                    call = {'type': 'tool', 'name': block.get('name'), 'input': block.get('input'),
                            'output': '', 'is_error': False}
                    calls[block.get('id')] = call
                    items.append(call)
        elif kind == 'user':
            content = event.get('message', {}).get('content', [])
            for block in content if isinstance(content, list) else []:
                if block.get('type') == 'tool_result' and block.get('tool_use_id') in calls:
                    call = calls[block['tool_use_id']]
                    call['output'] = clip(tool_result_text(block.get('content')))
                    call['is_error'] = bool(block.get('is_error'))
        elif kind == 'result':
            result = event
    return {
        'items': items,
        'reply': result.get('result') or '',
        'usage': result.get('usage') or {},
        'cost_usd': result.get('total_cost_usd'),
        'error': result.get('subtype') if result.get('is_error') else None,
    }


def parse_codex_turn(events):
    """One `codex exec --json` run as text, tool calls, the reply and usage."""
    items, notices, usage, error, thread = [], [], {}, None, None
    for event in events:
        kind = event.get('type')
        item = event.get('item') or {}
        if kind == 'thread.started':
            thread = event.get('thread_id')
        elif kind == 'item.completed':
            what = item.get('type')
            if what == 'agent_message' and item.get('text', '').strip():
                items.append({'type': 'text', 'text': item['text']})
            elif what == 'command_execution':
                code = item.get('exit_code')
                items.append({'type': 'tool', 'name': 'shell', 'input': item.get('command', ''),
                              'output': clip(item.get('aggregated_output', '')),
                              'is_error': code not in (0, None)})
            elif what == 'file_change':
                items.append({'type': 'tool', 'name': 'apply_patch', 'input': item.get('changes'),
                              'output': item.get('status', ''), 'is_error': item.get('status') == 'failed'})
            elif what == 'mcp_tool_call':
                items.append({'type': 'tool', 'name': f'mcp:{item.get("server")}.{item.get("tool")}',
                              'input': item.get('arguments'), 'output': clip(item.get('result') or ''),
                              'is_error': item.get('status') == 'failed'})
            elif what == 'error':
                notices.append(item.get('message', ''))
        elif kind == 'turn.completed':
            usage = event.get('usage') or {}
        elif kind in ('turn.failed', 'error'):
            error = (event.get('error') or {}).get('message') or event.get('message') or kind
    texts = [item['text'] for item in items if item['type'] == 'text']
    return {'items': items, 'reply': texts[-1] if texts else '', 'usage': usage, 'cost_usd': None,
            'error': error, 'notices': notices, 'thread_id': thread}


def narration(items):
    """Text the agent wrote before its last tool call: what it said while working."""
    last_tool = max((index for index, item in enumerate(items) if item['type'] == 'tool'), default=-1)
    return [item['text'] for item in items[:last_tool] if item['type'] == 'text']


def command_of(item):
    """The shell command of a tool call, for either client, or None."""
    if item['name'] == 'Bash' and isinstance(item['input'], dict):
        return item['input'].get('command')
    if item['name'] == 'shell' and isinstance(item['input'], str):
        return item['input']
    return None


def dialogue_op(command):
    """The dialogue subcommand a shell command ran, such as 'thread open', or None."""
    try:
        words = shlex.split(command)
    except ValueError:
        return None
    if len(words) >= 3 and words[0].endswith('sh') and words[1] in ('-c', '-lc'):
        return dialogue_op(words[2])
    for index, word in enumerate(words):
        if word.endswith('/bin/dialogue'):
            rest, skip = [], False
            for part in words[index + 1:]:
                if skip:
                    skip = False
                elif part in ('--client', '--session'):
                    skip = True
                elif part in ('&&', ';', '|', '||'):
                    break
                elif not part.startswith('--'):
                    rest.append(part)
            if not rest:
                return None
            grouped = ('thread', 'defaults', 'guideline', 'guidelines', 'situation', 'setup')
            return ' '.join(rest[:2]) if rest[0] in grouped and len(rest) > 1 else rest[0]
    return None


class ClaudeSession:
    """One `claude -p` process fed a user message per turn over stream-json."""

    def __init__(self, agent, plugin, workspace, state_dir, events_log, stderr_log, timeout):
        self.session_id = str(uuid.uuid4())
        self.timeout = timeout
        self.events_log = events_log
        self.init = None
        self.hook_output = None
        command = ['claude', '-p', '--model', agent['model'], '--setting-sources', 'project,local',
                   '--plugin-dir', str(plugin), '--input-format', 'stream-json',
                   '--output-format', 'stream-json', '--verbose', '--no-session-persistence',
                   '--session-id', self.session_id]
        if agent['effort']:
            command += ['--effort', agent['effort']]
        command += ['--allowedTools', *claude_allowed_tools(plugin)]
        self.command = command
        self.stderr = open(stderr_log, 'a', encoding='utf-8')
        self.process = subprocess.Popen(command, cwd=workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.stderr, text=True, bufsize=1,
                                        env=clean_env(DIALOGUE_STATE_DIR=str(state_dir)))
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def send(self, text, turn):
        started = time.monotonic()
        message = {'type': 'user', 'message': {'role': 'user', 'content': text}}
        events = []
        with open(self.events_log, 'a', encoding='utf-8') as log:
            log.write(json.dumps({'testbed_turn': turn, 'sent': text}) + '\n')
            try:
                self.process.stdin.write(json.dumps(message) + '\n')
                self.process.stdin.flush()
            except BrokenPipeError:
                return self._failed(events, started, 'claude exited before the turn')
            while True:
                remaining = self.timeout - (time.monotonic() - started)
                try:
                    line = self.lines.get(timeout=max(remaining, 0.1))
                except queue.Empty:
                    self.process.kill()
                    return self._failed(events, started, f'turn timed out after {self.timeout}s')
                if line is None:
                    return self._failed(events, started, f'claude exited with {self.process.wait()}')
                log.write(line)
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                events.append(event)
                if event.get('type') == 'system' and event.get('subtype') == 'init' and self.init is None:
                    self.init = {'model': event.get('model'), 'plugins': event.get('plugins'),
                                 'claude_code_version': event.get('claude_code_version')}
                if event.get('type') == 'system' and event.get('subtype') == 'hook_response' \
                        and self.hook_output is None and 'dialogue' in json.dumps(event.get('output', '')):
                    self.hook_output = event.get('output')
                if event.get('type') == 'result':
                    turn_result = parse_claude_turn(events)
                    turn_result['duration_s'] = round(time.monotonic() - started, 1)
                    return turn_result

    def _failed(self, events, started, error):
        turn_result = parse_claude_turn(events)
        turn_result.update(error=error, duration_s=round(time.monotonic() - started, 1))
        return turn_result

    def close(self):
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.kill()
        self.stderr.close()

    def injected_policy(self):
        """What the dialogue hook printed into this session, from the hook_response event."""
        if not self.hook_output:
            return None
        try:
            return json.loads(self.hook_output)['hookSpecificOutput']['additionalContext']
        except (ValueError, KeyError, TypeError):
            return None


class CodexHome:
    """A throwaway CODEX_HOME holding the user's auth, the plugin under test and nothing else."""

    def __init__(self, root, marketplace):
        self.path = Path(root) / 'codex-home'
        self.path.mkdir(parents=True)
        auth = Path(os.environ.get('CODEX_HOME', '~/.codex')).expanduser() / 'auth.json'
        if not auth.exists():
            raise RuntimeError(f'no Codex login at {auth}; run codex login first')
        (self.path / 'auth.json').symlink_to(auth)
        env = self.env()
        for args in (['plugin', 'marketplace', 'add', str(marketplace)], ['plugin', 'add', 'dialogue@testbed']):
            result = subprocess.run(['codex', *args], capture_output=True, text=True, env=env,
                                    stdin=subprocess.DEVNULL)
            if result.returncode != 0:
                raise RuntimeError(f'codex {" ".join(args)} failed: {result.stderr.strip()}')
        with open(self.path / 'config.toml', 'a', encoding='utf-8') as config:
            # Remote plugins from the account add context the test did not ask for,
            # and the dialogue tool needs DIALOGUE_STATE_DIR in its shell.
            config.write('\n[features]\nremote_plugin = false\n\n[shell_environment_policy]\ninherit = "all"\n')
        installed = sorted((self.path / 'plugins' / 'cache' / 'testbed' / 'dialogue').iterdir())
        self.plugin = installed[-1]

    def env(self, **extra):
        return clean_env(CODEX_HOME=str(self.path), **extra)

    def rollout(self, thread_id):
        found = sorted(self.path.glob(f'sessions/**/rollout-*-{thread_id}.jsonl'))
        return found[-1] if found else None


class CodexSession:
    """One Codex thread: `codex exec` for the first turn, `codex exec resume` for the rest."""

    def __init__(self, agent, home, workspace, state_dir, events_log, stderr_log, timeout):
        self.agent, self.home, self.workspace = agent, home, workspace
        self.state_dir, self.events_log, self.stderr_log = str(state_dir), events_log, stderr_log
        self.timeout = timeout
        self.session_id = None
        self.init = None
        self.commands = []

    def send(self, text, turn):
        started = time.monotonic()
        command = ['codex', 'exec'] + (['resume'] if self.session_id else [])
        command += ['--json', '--skip-git-repo-check', '--dangerously-bypass-hook-trust',
                    '-m', self.agent['model'],
                    '-c', 'sandbox_mode="workspace-write"',
                    '-c', f'sandbox_workspace_write.writable_roots={json.dumps([self.state_dir])}']
        if self.agent['effort']:
            command += ['-c', f'model_reasoning_effort={json.dumps(self.agent["effort"])}']
        command += ['--'] + ([self.session_id] if self.session_id else []) + [text]
        self.commands.append(command)
        try:
            result = subprocess.run(command, cwd=self.workspace, stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, timeout=self.timeout,
                                    env=self.home.env(DIALOGUE_STATE_DIR=self.state_dir))
            stdout, stderr, error = result.stdout, result.stderr, (
                f'codex exited with {result.returncode}' if result.returncode else None)
        except subprocess.TimeoutExpired as expired:
            stdout = expired.stdout or ''
            stderr = expired.stderr or ''
            stdout, stderr = (part.decode() if isinstance(part, bytes) else part for part in (stdout, stderr))
            error = f'turn timed out after {self.timeout}s'
        events = []
        with open(self.events_log, 'a', encoding='utf-8') as log:
            log.write(json.dumps({'testbed_turn': turn, 'sent': text}) + '\n')
            for line in stdout.splitlines():
                log.write(line + '\n')
                try:
                    events.append(json.loads(line))
                except ValueError:
                    pass
        with open(self.stderr_log, 'a', encoding='utf-8') as log:
            log.write(f'--- turn {turn}\n{stderr}')
        turn_result = parse_codex_turn(events)
        self.session_id = self.session_id or turn_result.get('thread_id')
        turn_result['error'] = turn_result['error'] or error
        turn_result['duration_s'] = round(time.monotonic() - started, 1)
        return turn_result

    def close(self):
        pass

    def injected_policy(self):
        return None


def check_installed(clients):
    missing = [client for client in clients if shutil.which(client) is None]
    if missing:
        raise RuntimeError(f'not on PATH: {", ".join(missing)}')


def version(client):
    result = subprocess.run([client, '--version'], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return result.stdout.strip() or result.stderr.strip()

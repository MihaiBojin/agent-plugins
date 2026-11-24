"""The dialogue plugin under test: copy it, seed its state, and render the policy it injects."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from matrix import THREAD_MODES, thread_mode

SEED_SESSION = 'testbed-seed'
RENDER_SESSION = 'testbed-render'


def snapshot(source, destination):
    """Copy the plugin so every case in a run reads the same files, even while the source changes."""
    source = Path(source).resolve()
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns('__pycache__', 'tests', '.DS_Store'))
    manifest = json.loads((source / '.claude-plugin' / 'plugin.json').read_text(encoding='utf-8'))
    git = {}
    for key, args in (('commit', ['rev-parse', 'HEAD']), ('dirty', ['status', '--porcelain', '--', '.'])):
        result = subprocess.run(['git', '-C', str(source), *args], capture_output=True, text=True)
        git[key] = result.stdout.strip() if result.returncode == 0 else None
    return {'source': str(source), 'path': str(destination), 'version': manifest.get('version'),
            'git_commit': git['commit'], 'git_dirty': bool(git['dirty'])}


def tool(plugin, state_dir, *args, client='claude', stdin=None):
    """Run bin/dialogue against state_dir and return what it printed."""
    command = [str(Path(plugin) / 'bin' / 'dialogue'), '--client', client]
    if args and args[0] != 'hook':
        command += ['--session', SEED_SESSION]
    env = {key: value for key, value in os.environ.items() if key not in ('CLAUDE_SESSION_ID', 'CODEX_THREAD_ID')}
    env['DIALOGUE_STATE_DIR'] = str(state_dir)
    result = subprocess.run([*command, *args], input=stdin, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        raise RuntimeError(f'dialogue {" ".join(args)} failed: {result.stderr.strip()}')
    return result.stdout


def settings_table(plugin):
    """Each setting the plugin has, with its default for new sessions."""
    with tempfile.TemporaryDirectory() as state:
        table = tool(plugin, state, 'settings')
    defaults = {}
    for line in table.splitlines():
        cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
        if len(cells) >= 3:
            defaults[cells[0]] = cells[2]
    return defaults


def fresh_defaults(plugin):
    """The settings a session gets right after enable, before anything else is changed.

    A plugin without the situation setting runs as situation none."""
    defaults = settings_table(plugin)
    flag = lambda key: defaults[key] == 'true'
    style = defaults['language_standard']
    return {
        'enabled': True,
        'comms': defaults['communication_profile'],
        'style': 'ste' if style == 'ste-inspired' else style,
        'situation': defaults.get('situation', 'none'),
        'signals': defaults['signaling'],
        'threads': thread_mode(flag('threads'), flag('focus'), flag('compact')),
        'guidelines': {},
    }


def seed(plugin, state_dir, config):
    """Write the configuration as the defaults, so the session the client starts snapshots it."""
    values = {'enabled': 'on' if config['enabled'] else 'off', 'comms': config['comms'],
              'style': config['style'], 'signals': config['signals'], **THREAD_MODES[config['threads']]}
    if config['situation'] != 'none':
        # none is the default, and the only value of a plugin without the setting.
        values['situation'] = config['situation']
    for key, value in values.items():
        tool(plugin, state_dir, 'defaults', 'set', key, value)
    for identifier, enabled in sorted(config['guidelines'].items()):
        tool(plugin, state_dir, 'guideline', '--default', 'enable' if enabled else 'disable', identifier)


def hook_commands(plugin, client):
    """Every SessionStart command the plugin declares for the client, in order."""
    name = 'hooks.json' if client == 'claude' else 'codex.json'
    config = json.loads((Path(plugin) / 'hooks' / name).read_text(encoding='utf-8'))
    return [hook['command'] for group in config['hooks'].get('SessionStart', [])
            for hook in group.get('hooks', []) if hook.get('type') == 'command']


def render_parts(plugin, state_dir, client='claude'):
    """What each SessionStart hook injects into a new session seeded from state_dir; empty outputs left out.

    Claude Code inlines each part only up to its limit, so the parts are measured one by one."""
    payload = json.dumps({'session_id': RENDER_SESSION, 'source': 'startup', 'hook_event_name': 'SessionStart'})
    parts = []
    with tempfile.TemporaryDirectory() as scratch:
        copy = Path(scratch) / 'state'
        shutil.copytree(state_dir, copy)
        env = {key: value for key, value in os.environ.items() if key not in ('CLAUDE_SESSION_ID', 'CODEX_THREAD_ID')}
        env.update(DIALOGUE_STATE_DIR=str(copy), CLAUDE_PLUGIN_ROOT=str(plugin), PLUGIN_ROOT=str(plugin))
        for command in hook_commands(plugin, client):
            result = subprocess.run(['bash', '-c', command], input=payload, capture_output=True, text=True, env=env)
            if result.returncode != 0:
                raise RuntimeError(f'hook {command} failed: {result.stderr.strip()}')
            if result.stdout.strip():
                parts.append(json.loads(result.stdout)['hookSpecificOutput']['additionalContext'])
    return parts


def render(plugin, state_dir, client='claude'):
    """The whole policy a new session seeded from state_dir starts with: every hook part, joined."""
    return '\n\n'.join(render_parts(plugin, state_dir, client))


def without_session(text, session):
    """The policy with the session ID replaced, so two sessions' policies compare equal."""
    return re.sub(re.escape(session), 'SESSION', text) if session else text


def read_session(state_dir, client):
    """The one session record a case's client wrote, or None before it wrote one."""
    records = sorted((Path(state_dir) / 'sessions' / client).glob('*.json'))
    records = [path for path in records if path.stem not in (SEED_SESSION, RENDER_SESSION)]
    if not records:
        return None
    return json.loads(records[-1].read_text(encoding='utf-8'))


def terms(plugin):
    """Marker words and framework field names, for spotting them in replies."""
    policy = Path(plugin) / 'policy'
    signals = json.loads((policy / 'signals.json').read_text(encoding='utf-8'))
    # Dialogue 0.16.0 and later ship no situations.json.
    path = policy / 'situations.json'
    situations = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    guidelines = json.loads((policy / 'guidelines.json').read_text(encoding='utf-8'))
    return {
        'guidelines': {entry['id']: entry['name'] for entry in guidelines},
        'intents': [item['id'] for item in signals['intents']],
        'responses': [item['id'] for item in signals['responses']],
        'frameworks': {name: [field for field, _ in item['fields']] for name, item in situations.items()},
    }

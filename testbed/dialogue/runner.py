"""Run cases: a fresh workspace and state for each, the scripted turns, and the files each variant keeps."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import uuid

import clients
from clients import CLAUDE_INLINE_LIMIT
import cost
from matrix import HERE, slug
import plugin
import report

FIXTURE = HERE / 'fixture'


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def codex_limit(plugin_path):
    hooks = json.loads((Path(plugin_path) / 'hooks' / 'codex.json').read_text(encoding='utf-8'))
    for group in hooks['hooks'].get('SessionStart', []):
        for hook in group.get('hooks', []):
            if 'additionalContextLimit' in hook:
                return hook['additionalContextLimit']
    return None


def policy_notes(part_chars, client, codex_chars_limit):
    """Each hook part is limited on its own, so the notes name the parts over their client's limit."""
    notes = []
    for number, chars in enumerate(part_chars, 1):
        name = f'hook part {number}' if len(part_chars) > 1 else 'the policy'
        if client == 'claude' and chars > CLAUDE_INLINE_LIMIT:
            notes.append(f'{name} is over the {CLAUDE_INLINE_LIMIT:,}-character inline limit of Claude Code: '
                         'the model gets a preview and a file path')
        if client == 'codex' and codex_chars_limit and chars > codex_chars_limit:
            notes.append(f'{name} is over the {codex_chars_limit:,}-character additionalContextLimit in '
                         'hooks/codex.json')
    return notes


def write_marketplace(marketplace):
    """The local marketplace Codex installs the plugin copy from."""
    (marketplace / '.agents' / 'plugins').mkdir(parents=True)
    (marketplace / '.agents' / 'plugins' / 'marketplace.json').write_text(json.dumps({
        'name': 'testbed', 'interface': {'displayName': 'testbed'},
        'plugins': [{'name': 'dialogue', 'source': {'source': 'local', 'path': './plugins/dialogue'},
                     'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
                     'category': 'Developer Tools'}]}, indent=2), encoding='utf-8')


def drop_lines(plugin_dir, drops):
    """Remove each `FILE:LINE` from the plugin copy; line numbers refer to the file before any removal."""
    by_file = {}
    for drop in drops:
        path, _, number = drop.rpartition(':')
        by_file.setdefault(path, set()).add(int(number))
    for path, numbers in by_file.items():
        target = Path(plugin_dir) / path
        lines = target.read_text(encoding='utf-8').splitlines(keepends=True)
        target.write_text(''.join(line for index, line in enumerate(lines, 1) if index not in numbers),
                          encoding='utf-8')


def placeholder_thread(state):
    """The thread {active} names and the option {recommended} names, from the saved state."""
    threads = (state or {}).get('threads') or {}
    open_ids = sorted((key for key, item in threads.items() if item['status'] == 'open'),
                      key=lambda key: [int(part) for part in key.split('.')])
    active = (state or {}).get('active')
    chosen = active if active in open_ids else (open_ids[0] if open_ids else '1')
    options = (threads.get(chosen) or {}).get('options') or {}
    live = [letter for letter, option in options.items() if option['status'] == 'live']
    recommended = [letter for letter in live if options[letter].get('recommended')]
    return chosen, (recommended or live or ['a'])[0]


def fill(template, client, state):
    """A scenario turn with its placeholders replaced: {cmd}, {active} and {recommended}."""
    thread, letter = placeholder_thread(state)
    command = '/dialogue:' if client == 'claude' else '$dialogue:'
    return template.replace('{cmd}', command).replace('{active}', thread).replace('{recommended}', letter)


def git(path, *args):
    return subprocess.run(['git', '-C', str(path), '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
                           '-c', 'user.name=testbed', '-c', 'user.email=testbed@example.invalid', *args],
                          capture_output=True, text=True, stdin=subprocess.DEVNULL)


def make_workspace(path):
    shutil.copytree(FIXTURE, path, ignore=shutil.ignore_patterns('__pycache__', '.DS_Store'))
    for args in (['init', '-q'], ['add', '-A'], ['commit', '-q', '-m', 'fixture']):
        result = git(path, *args)
        if result.returncode != 0:
            raise RuntimeError(f'git {args[0]} in the workspace failed: {result.stderr.strip()}')


def workspace_diff(path):
    git(path, 'add', '-A')
    return git(path, 'diff', '--cached').stdout


def forget_claude_project(workspace):
    """Remove the directory Claude Code keeps for the case's workspace, which only this case used."""
    root = Path(os.environ.get('CLAUDE_CONFIG_DIR', Path.home() / '.claude')) / 'projects'
    for path in {str(workspace), os.path.realpath(workspace)}:
        name = re.sub(r'[^A-Za-z0-9]', '-', path)
        if 'dialogue-testbed' in name and (root / name).is_dir():
            shutil.rmtree(root / name, ignore_errors=True)


class Run:
    """One testbed run: the plugin snapshot, the client setup, and the cases it executes."""

    def __init__(self, out_dir, work_root, plugin_source, agents, settings):
        self.out = Path(out_dir)
        # Resolved, because the policy prints the tool's resolved path, and Claude Code
        # allows a command only when it starts with the exact path in --allowedTools.
        self.work = Path(work_root).resolve() / self.out.name
        self.agents = agents
        self.settings = settings
        self.lock = threading.Lock()
        self.spent = 0.0
        self.failures = []
        self.prices = cost.pricing()
        self.out.mkdir(parents=True, exist_ok=True)
        if self.work.exists():
            shutil.rmtree(self.work)
        marketplace = self.work / 'marketplace'
        self.plugin_info = plugin.snapshot(plugin_source, marketplace / 'plugins' / 'dialogue')
        self.plugin_path = Path(self.plugin_info['path'])
        write_marketplace(marketplace)
        used = sorted({agent['client'] for agent in agents})
        clients.check_installed(used)
        self.versions = {client: clients.version(client) for client in used}
        self.codex = clients.CodexHome(self.work, marketplace) if 'codex' in used else None
        self.patched = {}
        self.codex_limit = codex_limit(self.plugin_path)
        self.terms = plugin.terms(self.plugin_path)

    def installed(self, config, client):
        """The plugin a case runs: the snapshot, or a copy with the configuration's policy lines removed.

        Returns the plugin directory for Claude and the Codex home for Codex. A copy is made once per set of
        removed lines and shared by every case that removes the same ones."""
        drops = tuple(config.get('drops') or ())
        if not drops:
            return self.plugin_path if client == 'claude' else self.codex
        key = (drops, client)
        with self.lock:
            if key not in self.patched:
                root = self.work / 'patched' / uuid.uuid4().hex[:12]
                marketplace = root / 'marketplace'
                shutil.copytree(self.plugin_path, marketplace / 'plugins' / 'dialogue')
                drop_lines(marketplace / 'plugins' / 'dialogue', drops)
                write_marketplace(marketplace)
                self.patched[key] = (marketplace / 'plugins' / 'dialogue' if client == 'claude'
                                     else clients.CodexHome(root, marketplace))
            return self.patched[key]

    def write_manifest(self, extra):
        path = self.out / 'run.json'
        manifest = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'started': now()}
        manifest.update({'agents': self.agents, 'plugin': self.plugin_info, 'client_versions': self.versions,
                         'terms': self.terms, 'claude_inline_limit': CLAUDE_INLINE_LIMIT,
                         'codex_context_limit': self.codex_limit, 'settings': self.settings, **extra})
        report.write_json(path, manifest)

    def execute(self, cases, jobs, max_usd=None):
        done = {'count': 0}
        total = len(cases)

        def one(case):
            result = self.run_case(case, max_usd)
            with self.lock:
                done['count'] += 1
                print(f'[{done["count"]}/{total}] {result}', flush=True)

        with ThreadPoolExecutor(max_workers=max(jobs, 1)) as pool:
            for future in [pool.submit(one, case) for case in cases]:
                future.result()

    def run_case(self, case, max_usd):
        case_dir = self.out / 'cases' / case['key']
        variant_path = case_dir / 'variant.json'
        if variant_path.exists() and report.read_json(variant_path).get('status') == 'complete':
            return f'kept     {case["key"]}'
        with self.lock:
            if max_usd is not None and self.spent >= max_usd:
                return f'budget   {case["key"]} (spent ${self.spent:.2f} of ${max_usd:.2f})'
        if case_dir.exists():
            shutil.rmtree(case_dir)
        case_dir.mkdir(parents=True)
        work = self.work / 'cases' / uuid.uuid4().hex[:12]
        try:
            variant = self.converse(case, case_dir, work)
        except Exception as failure:  # Setup failed: keep nothing, so the next run retries the case.
            shutil.rmtree(case_dir, ignore_errors=True)
            with self.lock:
                self.failures.append({'case': case['key'], 'error': f'{type(failure).__name__}: {failure}'})
            return f'failed   {case["key"]}: {type(failure).__name__}: {failure}'
        finally:
            shutil.rmtree(work, ignore_errors=True)
            if case['agent']['client'] == 'claude':
                forget_claude_project(work / 'workspace')
        with self.lock:
            self.spent += variant.get('cost_usd') or 0
        return (f'{variant["status"]:<8} {case["key"]} {len(variant["turn_costs"])} turns '
                f'{report.format_usd(variant.get("cost_usd"))} {variant["duration_s"]:.0f}s')

    def converse(self, case, case_dir, work):
        agent, config = case['agent'], case['config']
        client = agent['client']
        workspace, state = work / 'workspace', work / 'state'
        make_workspace(workspace)
        plugin.seed(self.plugin_path, state, config)
        target = self.installed(config, client)
        parts = plugin.render_parts(target.plugin if client == 'codex' else target, state, client)
        policy = '\n\n'.join(parts)
        (case_dir / 'policy.md').write_text(policy, encoding='utf-8')
        variant = {'agent': agent, 'scenario': case['scenario'], 'config': config, 'slug': slug(config),
                   'repeat': case['repeat'], 'suites': case['suites'], 'plugin': self.plugin_info,
                   'client_version': self.versions[client], 'started': now(), 'status': 'running',
                   'policy_chars': len(policy), 'policy_parts': [len(part) for part in parts],
                   'policy_notes': policy_notes([len(part) for part in parts], client, self.codex_limit)}
        report.write_json(case_dir / 'variant.json', variant)
        logs = {'events_log': case_dir / 'events.jsonl', 'stderr_log': case_dir / 'stderr.log',
                'timeout': self.settings['turn_timeout']}
        if client == 'claude':
            session = clients.ClaudeSession(agent, target, workspace, state, **logs)
        else:
            session = clients.CodexSession(agent, target, workspace, state, **logs)
        turns, error = [], None
        try:
            for number, template in enumerate(case['scenario']['turns'], 1):
                sent = fill(template, client, plugin.read_session(state, client))
                turn = session.send(sent, number)
                turn.update(template=template, sent=sent, state_after=plugin.read_session(state, client))
                turns.append(turn)
                if turn.get('error'):
                    error = f'turn {number}: {turn["error"]}'
                    break
        except Exception as failure:  # A crash in one case must not stop the others.
            error = f'{type(failure).__name__}: {failure}'
        finally:
            session.close()
        self.account(client, agent, turns)
        diff = workspace_diff(workspace)
        if diff:
            (case_dir / 'workspace.diff').write_text(diff, encoding='utf-8')
        variant.update(self.client_facts(session, client, parts, case_dir))
        variant.update(status='error' if error else 'complete', error=error, finished=now(),
                       session_id=session.session_id, turn_costs=[turn.get('cost_usd') for turn in turns],
                       cost_usd=None if any(turn.get('cost_usd') is None for turn in turns)
                       else round(sum(turn['cost_usd'] for turn in turns), 6),
                       duration_s=sum(turn.get('duration_s') or 0 for turn in turns))
        report.write_json(case_dir / 'turns.json', turns)
        report.write_json(case_dir / 'variant.json', variant)
        report.write_case(case_dir, self.terms)
        return variant

    def account(self, client, agent, turns):
        """Set cost_usd on each turn: what Claude reported for it, or Codex tokens at the listed rates."""
        model_rates = cost.rates(self.prices, agent)
        previous = 0.0
        for turn in turns:
            turn['tokens'] = cost.tokens(client, turn.get('usage'))
            if client == 'claude':
                # total_cost_usd is the running total of the whole process.
                reported = turn.get('cost_usd')
                turn['reported_total_usd'] = reported
                turn['cost_usd'] = None if reported is None else round(reported - previous, 6)
                previous = reported if reported is not None else previous
            else:
                turn['cost_usd'] = cost.price(model_rates, turn['tokens'])

    def client_facts(self, session, client, parts, case_dir):
        facts = {'client_init': session.init}
        if client == 'claude':
            injected = session.injected_policy()
            # The hook parts may arrive in any order, so compare them as a set.
            facts['hook_policy_matches_render'] = None if injected is None else (
                sorted(plugin.without_session(part, session.session_id) for part in injected)
                == sorted(plugin.without_session(part, plugin.RENDER_SESSION) for part in parts))
            facts['claude_command'] = session.command
        else:
            rollout = self.codex.rollout(session.session_id) if session.session_id else None
            if rollout:
                shutil.copy(rollout, case_dir / 'codex-rollout.jsonl')
                lines = rollout.read_text(encoding='utf-8').splitlines()
                facts['policy_injections'] = sum('"developer"' in line and 'Dialogue is ' in line
                                                 and '"response_item"' in line for line in lines)
            facts['codex_commands'] = session.commands
        return facts

    def finish(self, extra):
        rows = report.write_index(self.out)
        self.write_manifest({'finished': now(), 'spent_usd': round(self.spent, 6), 'failures': self.failures,
                             'variants': rows[0], 'turn_rows': rows[1], **extra})
        shutil.rmtree(self.work, ignore_errors=True)

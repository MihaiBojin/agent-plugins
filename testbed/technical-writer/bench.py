#!/usr/bin/env python3
"""Benchmark the write-technical-prose skill: each task written with every rule, without the plugin, and with each rule
or group of rules removed, then measured for simplicity and graded against every rule.

  plan     List the sessions a run would start, and estimate tokens and dollars.
  run      Write each document, measure it and grade it. Each case gets its own directory under out/.
  report   Rebuild bench.md and bench.csv for a run directory.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
# The dialogue testbed's client parsers, pricing, judge client and statistics.
sys.path.insert(0, str(HERE.parent / 'dialogue'))
sys.dont_write_bytecode = True

import clients  # noqa: E402
import cost  # noqa: E402
import judge as judging  # noqa: E402
import matrix  # noqa: E402
import grade  # noqa: E402
import measure  # noqa: E402
import results  # noqa: E402
import skill  # noqa: E402

PLUGIN_NAME = 'technical-writer'
DEFAULT_PLUGIN = HERE.parents[1] / 'plugins' / PLUGIN_NAME
DEFAULT_AGENTS = ('claude:haiku', 'codex:gpt-6-luna:low')
DEFAULT_JUDGE = 'claude:sonnet'
OUT = HERE / 'out'
DEFAULT_WORK = Path(os.environ.get('TECHNICAL_WRITER_BENCH_WORK') or
                    Path(tempfile.gettempdir()) / 'technical-writer-bench')
TIMEOUT = 600
# Tokens per session until a run has measured them: the skill and a genre file read, one document written.
SESSION_TOKENS = {'claude': {'input': 50, 'cache_write': 25_000, 'cache_read': 60_000, 'output': 2_000},
                  'codex': {'input': 30_000, 'cache_write': 0, 'cache_read': 60_000, 'output': 3_000}}
GRADE_TOKENS = {'input': 9_000, 'cache_write': 0, 'cache_read': 0, 'output': 1_000}
FRONT_MATTER = re.compile(r'\A---\n.*?\n---\n', re.DOTALL)
# Configurations with the plugin name the skill, so a short task cannot skip it and leave every rule untested.
INVOKE = f'Use the {skill.NAME} skill.\n\n'


def tasks(plugin):
    """Each task's ID and prompt: an eval case's prompt.md, or a prompt of its own."""
    result = []
    for task in json.loads((HERE / 'data' / 'tasks.json').read_text(encoding='utf-8')):
        text = task.get('prompt')
        if task.get('eval'):
            text = FRONT_MATTER.sub('', (Path(plugin) / 'evals' / task['eval'] / 'prompt.md').read_text(
                encoding='utf-8')).strip()
        result.append({'id': task['id'], 'prompt': text})
    return result


def cases(plugin, agents, kind, repeat, task_ids=(), config_match=()):
    configs = skill.units(plugin, kind)
    chosen = [task for task in tasks(plugin) if not task_ids or task['id'] in task_ids]
    names = [name for name in configs if not config_match or any(part in name for part in config_match)]
    return [{'agent': agent, 'task': task, 'config': name, 'spans': configs[name], 'repeat': index,
             'key': f'{agent["label"]}/{task["id"]}/{name}/r{index}'}
            for agent in agents for name in names for task in chosen for index in range(1, repeat + 1)]


def estimate(selected, judge_agent):
    prices = cost.pricing()
    rows = {}
    for case in selected:
        agent = case['agent']
        row = rows.setdefault(agent['label'], {'agent': agent, 'sessions': 0, 'usd': 0.0})
        row['sessions'] += 1
        usd = cost.price(cost.rates(prices, agent), SESSION_TOKENS[agent['client']])
        row['usd'] = None if usd is None or row['usd'] is None else row['usd'] + usd
    grading = cost.price(cost.rates(prices, judge_agent), GRADE_TOKENS)
    return list(rows.values()), None if grading is None else grading * len(selected)


class Bench:
    def __init__(self, out, work, plugin, judge_agent):
        self.out, self.plugin = Path(out), Path(plugin)
        self.work = Path(work) / self.out.name
        self.rules = skill.rules(plugin)
        self.judge = judging.Judge(judge_agent, self.make('judge'))
        self.homes, self.lock, self.spent = {}, threading.Lock(), 0.0

    def make(self, *parts):
        path = self.work.joinpath(*parts)
        path.mkdir(parents=True, exist_ok=True)
        return path

    def copy(self, config, spans):
        """The plugin copy a configuration runs, inside a local marketplace Codex can install from."""
        marketplace = self.work / 'plugins' / config.replace('*', 'group-')
        target = marketplace / 'plugins' / PLUGIN_NAME
        if not target.exists():
            skill.patched(self.plugin, spans, target)
            (marketplace / '.agents' / 'plugins').mkdir(parents=True)
            (marketplace / '.agents' / 'plugins' / 'marketplace.json').write_text(json.dumps({
                'name': 'testbed', 'interface': {'displayName': 'testbed'},
                'plugins': [{'name': PLUGIN_NAME, 'source': {'source': 'local', 'path': f'./plugins/{PLUGIN_NAME}'},
                             'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
                             'category': 'Developer Tools'}]}, indent=2), encoding='utf-8')
        return marketplace, target

    def codex_home(self, config, spans):
        with self.lock:
            if config not in self.homes:
                marketplace = self.copy(config, spans)[0] if spans is not None else None
                self.homes[config] = clients.CodexHome(self.make('homes', config.replace('*', 'group-')),
                                                       marketplace, PLUGIN_NAME)
            return self.homes[config]

    def write(self, case, case_dir):
        agent, workspace = case['agent'], self.make('workspaces', uuid.uuid4().hex[:12])
        events_log, started = case_dir / 'events.jsonl', time.monotonic()
        if agent['client'] == 'claude':
            command = ['claude', '-p', '--model', agent['model'], '--setting-sources', 'project,local',
                       '--no-session-persistence', '--output-format', 'stream-json', '--verbose',
                       '--allowedTools', 'Read', 'Glob', 'Grep', 'Skill']
            if case['spans'] is not None:
                with self.lock:
                    command += ['--plugin-dir', str(self.copy(case['config'], case['spans'])[1])]
            if agent['effort']:
                command += ['--effort', agent['effort']]
            env = clients.clean_env()
        else:
            home = self.codex_home(case['config'], case['spans'])
            command = ['codex', 'exec', '--json', '--skip-git-repo-check', '--ephemeral', '-s', 'read-only',
                       '-m', agent['model']]
            if agent['effort']:
                command += ['-c', f'model_reasoning_effort={json.dumps(agent["effort"])}']
            env = home.env()
        try:
            result = subprocess.run([*command, '--', prompt_for(case)], cwd=workspace, env=env,
                                    capture_output=True, text=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL)
            stdout, stderr, error = result.stdout, result.stderr, (
                f'{agent["client"]} exited with {result.returncode}' if result.returncode else None)
        except subprocess.TimeoutExpired as expired:
            stdout, stderr = (part.decode() if isinstance(part, bytes) else (part or '')
                              for part in (expired.stdout, expired.stderr))
            error = f'timed out after {TIMEOUT}s'
        events_log.write_text(stdout, encoding='utf-8')
        (case_dir / 'stderr.log').write_text(stderr, encoding='utf-8')
        events = []
        for line in stdout.splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
        parse = clients.parse_claude_turn if agent['client'] == 'claude' else clients.parse_codex_turn
        turn = parse(events)
        usage = cost.tokens(agent['client'], turn['usage'])
        spent = turn['cost_usd'] if turn['cost_usd'] is not None else \
            cost.price(cost.rates(cost.pricing(), agent), usage)
        return {'reply': turn['reply'], 'error': turn['error'] or error, 'usage': usage, 'cost_usd': spent,
                'duration_s': round(time.monotonic() - started, 1), 'skill_fired': fired(turn['items'])}

    def run_case(self, case, max_usd):
        case_dir = self.out / 'cases' / case['agent']['label'] / case['task']['id'] / case['config'] / \
            f'r{case["repeat"]}'
        record_path = case_dir / 'case.json'
        if record_path.exists() and json.loads(record_path.read_text(encoding='utf-8'))['status'] == 'complete':
            return 'kept'
        if max_usd is not None and self.spent >= max_usd:
            return 'skipped'
        case_dir.mkdir(parents=True, exist_ok=True)
        written = self.write(case, case_dir)
        (case_dir / 'reply.md').write_text(written['reply'], encoding='utf-8')
        metrics = measure.measure(written['reply'])
        (case_dir / 'metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
        graded = self.grade(case, written['reply']) if written['reply'] and not written['error'] else None
        if graded:
            (case_dir / 'grades.json').write_text(json.dumps(graded, indent=2), encoding='utf-8')
        status = 'complete' if graded and graded['verdicts'] is not None else 'failed'
        skill_chars = None if case['spans'] is None else (
            self.work / 'plugins' / case['config'].replace('*', 'group-') / 'plugins' / PLUGIN_NAME /
            skill.SKILL).stat().st_size
        record = {'agent': case['agent'], 'task': case['task']['id'], 'config': case['config'],
                  'repeat': case['repeat'], 'status': status, 'error': written['error'],
                  'skill_fired': written['skill_fired'], 'skill_chars': skill_chars,
                  'usage': written['usage'], 'cost_usd': written['cost_usd'], 'duration_s': written['duration_s'],
                  'grade_cost_usd': graded['cost_usd'] if graded else None}
        record_path.write_text(json.dumps(record, indent=2), encoding='utf-8')
        with self.lock:
            self.spent += (written['cost_usd'] or 0) + ((graded or {}).get('cost_usd') or 0)
        return status

    def grade(self, case, reply):
        ids = [rule['id'] for rule in self.rules]
        text, spent, error = self.judge.ask(grade.SYSTEM, grade.prompt(case['task']['prompt'], self.rules, reply))
        verdicts = grade.parse(text, ids)
        return {'verdicts': verdicts, 'reasons': grade.reasons(text), 'cost_usd': spent, 'error': error, 'raw': text}

    def execute(self, selected, jobs, max_usd):
        done = [0]

        def one(case):
            status = self.run_case(case, max_usd)
            with self.lock:
                done[0] += 1
                print(f'[{done[0]}/{len(selected)}] {status} {case["key"]}', flush=True)

        with ThreadPoolExecutor(max_workers=max(jobs, 1)) as pool:
            for future in [pool.submit(one, case) for case in selected]:
                future.result()


PROSE_READ = re.compile(
    r"""(?:^|[\s'";|&(])(?:cat|head|tail|sed|awk|nl|less|more)\s+[^;|&\n]*?(?<![\w-])"""
    + re.escape(skill.SKILL.as_posix()) + r"""(?=$|[\s'";|&)])"""
)


def fired(items):
    """Detect an invocation of the prose skill or a read of its own SKILL.md."""
    for item in items:
        if item['type'] != 'tool' or item.get('is_error'):
            continue
        name, arguments = item['name'], item.get('input')
        if name == 'Skill' and isinstance(arguments, dict):
            if arguments.get('skill') in (skill.NAME, f'{PLUGIN_NAME}:{skill.NAME}'):
                return True
        if name == 'Read' and isinstance(arguments, dict):
            if Path(arguments.get('file_path', '')).parts[-3:] == skill.SKILL.parts:
                return True
        if name == 'shell' and isinstance(arguments, str) and PROSE_READ.search(arguments):
            return True
    return False


def prompt_for(case):
    """The task as sent: `off` and `unprompted` get it as written, every other configuration also names the skill."""
    named = case['spans'] is not None and case.get('config') != 'unprompted'
    return INVOKE + case['task']['prompt'] if named else case['task']['prompt']


def new_out_dir():
    path = OUT / f'{datetime.now().strftime("%Y%m%d-%H%M%S")}-run'
    path.mkdir(parents=True)
    latest = OUT / 'latest-run'
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(path.name)
    return path


def command_plan(args, selected):
    rows, grading = estimate(selected, matrix.parse_agent(args.judge))
    configs = sorted({case['config'] for case in selected})
    print(f'{len(configs)} configurations x {len({case["task"]["id"] for case in selected})} tasks x{args.repeat}: '
          f'{len(selected)} sessions.')
    for row in rows:
        usd = 'no rate' if row['usd'] is None else f'${row["usd"]:.2f}'
        print(f'  {row["agent"]["label"]:<28} {row["sessions"]:>5} sessions  {usd}')
    print(f'  grading by {args.judge}: {len(selected)} calls, '
          f'{"no rate" if grading is None else f"${grading:.2f}"}')
    print('Estimates use the token counts in bench.py; a ChatGPT sign-in draws on plan limits instead of dollars.')
    if getattr(args, 'list', False):
        for case in selected:
            print(case['key'])


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    result.add_argument('--plugin', type=Path, default=DEFAULT_PLUGIN,
                        help=f'the technical-writer plugin to test (default: {DEFAULT_PLUGIN})')
    sub = result.add_subparsers(dest='command', required=True)
    for name in ('plan', 'run'):
        command = sub.add_parser(name, help='estimate a run' if name == 'plan' else 'execute a run')
        command.add_argument('--agent', action='append', metavar='CLIENT:MODEL[:EFFORT]',
                             help=f'claude:MODEL or codex:MODEL, repeatable (default: {" ".join(DEFAULT_AGENTS)})')
        command.add_argument('--units', choices=('groups', 'rules', 'all'), default='groups',
                             help='remove one group of rules per configuration, one rule, or both (default: groups)')
        command.add_argument('--task', action='append', help='only this task ID, repeatable')
        command.add_argument('--config', action='append', metavar='TEXT',
                             help='only configurations whose name contains TEXT, repeatable')
        command.add_argument('--repeat', type=int, default=6, help='sessions per case (default: 6)')
        command.add_argument('--judge', default=DEFAULT_JUDGE, metavar='CLIENT:MODEL[:EFFORT]',
                             help=f'the model that grades each document (default: {DEFAULT_JUDGE})')
        command.add_argument('--jobs', type=int, default=6, help='sessions at a time')
        if name == 'plan':
            command.add_argument('--list', action='store_true', help='print every case')
        else:
            command.add_argument('--out', help='output directory; an existing one keeps its complete cases')
            command.add_argument('--work', type=Path, default=DEFAULT_WORK,
                                 help=f'scratch space for plugin copies and workspaces (default: {DEFAULT_WORK})')
            command.add_argument('--yes', action='store_true', help='start without asking')
            command.add_argument('--max-usd', type=float, help='stop starting sessions after spending this much')
    rebuild = sub.add_parser('report', help='rebuild bench.md and bench.csv')
    rebuild.add_argument('run_dir', type=Path)
    return result


def main():
    args = parser().parse_args()
    args.plugin = args.plugin.resolve()
    if args.command == 'report':
        print(f'{results.write(args.run_dir, skill.rules(json.loads((args.run_dir / "run.json").read_text())["plugin"]))} '
              f'cases. Report: {args.run_dir / "bench.md"}')
        return
    agents = [matrix.parse_agent(text) for text in (args.agent or DEFAULT_AGENTS)]
    selected = cases(args.plugin, agents, args.units, args.repeat, args.task or (), args.config or ())
    command_plan(args, selected)
    if args.command == 'plan':
        return
    if not args.yes:
        if not sys.stdin.isatty():
            sys.exit('Pass --yes to start without a prompt.')
        if input(f'Start {len(selected)} sessions? [y/N] ').strip().lower() not in ('y', 'yes'):
            sys.exit('Nothing started.')
    out = Path(args.out) if args.out else new_out_dir()
    out.mkdir(parents=True, exist_ok=True)
    (out / 'run.json').write_text(json.dumps({'plugin': str(args.plugin), 'units': args.units, 'repeat': args.repeat,
                                              'judge': args.judge, 'agents': [a['label'] for a in agents],
                                              'started': datetime.now().isoformat(timespec='seconds')}, indent=2),
                                  encoding='utf-8')
    bench = Bench(out, args.work, args.plugin, matrix.parse_agent(args.judge))
    try:
        bench.execute(selected, args.jobs, args.max_usd)
    finally:
        count = results.write(out, bench.rules)
    print(f'Spent ${bench.spent:.4f} where measured. {count} cases. Report: {out / "bench.md"}')


if __name__ == '__main__':
    main()

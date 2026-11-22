"""A blind pairwise judge: which of two replies to the same scenario is better, without knowing their settings.

Each configuration is compared with the base configuration, and the base with dialogue disabled, for the
same agent, scenario and repeat. The judge sees the user turns, both sets of replies and the fixture's facts
for the scenario, never the settings. Every pair is judged twice, with the sides swapped, so a preference for
the first or second position cancels out.
"""

from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading

import clients
import cost
from matrix import load_json
import report

SIDES = ('A', 'B')
PROMPT_CHARS_PER_TOKEN = 4
OUTPUT_TOKENS = 500

SYSTEM = """You judge two assistant conversations that answer the same user turns in the same software repository.
Score each conversation from 1 to 5 on every criterion, then pick the better one, or a tie when neither is clearly
better. Judge only what the replies say. Ignore formatting conventions unless they help or hurt the reader.
Reply with one JSON object and nothing else:
{"scores": {"A": {CRITERIA}, "B": {CRITERIA}}, "winner": "A" | "B" | "tie", "reason": "one or two sentences"}"""


def conversation(turns):
    parts = []
    for number, turn in enumerate(turns, 1):
        parts.append(f'User, turn {number}:\n{turn["sent"]}\n\nAssistant, turn {number}:\n{turn.get("reply") or "(no reply)"}')
    return '\n\n'.join(parts)


def prompt(scenario, rubric, first, second):
    facts = '\n'.join(f'- {fact}' for fact in rubric['facts'].get(scenario, [])) or '- none listed'
    criteria = '\n'.join(f'- {name}: {meaning}' for name, meaning in rubric['criteria'].items())
    return (f'Criteria:\n{criteria}\n\nFacts about the repository for this scenario:\n{facts}\n\n'
            f'=== Conversation A ===\n{conversation(first)}\n\n=== Conversation B ===\n{conversation(second)}\n')


def system_prompt(rubric):
    fields = ', '.join(f'"{name}": 1-5' for name in rubric['criteria'])
    return SYSTEM.replace('{CRITERIA}', '{' + fields + '}')


def parse(text):
    match = re.search(r'\{.*\}', text or '', re.DOTALL)
    if not match:
        return None
    try:
        value = json.loads(match.group(0))
    except ValueError:
        return None
    return value if value.get('winner') in ('A', 'B', 'tie') else None


def pairs(run_dir, base_slug, with_disabled=True):
    """(variant, base) for every complete variant and the base it is compared with."""
    run_dir = Path(run_dir)
    found = {}
    for case_dir in report.case_dirs(run_dir):
        variant = report.read_json(case_dir / 'variant.json')
        if variant['status'] == 'complete' and variant['scenario']['kind'] == 'task':
            key = (variant['agent']['label'], variant['scenario']['id'], variant['repeat'])
            found.setdefault(key, {})[variant['slug']] = case_dir
    result = []
    for (agent, scenario, repeat), by_slug in sorted(found.items()):
        if base_slug not in by_slug:
            continue
        for slug, case_dir in sorted(by_slug.items()):
            if slug != base_slug:
                result.append({'agent': agent, 'scenario': scenario, 'repeat': repeat, 'config': slug,
                               'variant': case_dir, 'base': by_slug[base_slug], 'base_slug': base_slug})
        if with_disabled and 'disabled' in by_slug:
            result.append({'agent': agent, 'scenario': scenario, 'repeat': repeat, 'config': base_slug,
                           'variant': by_slug[base_slug], 'base': by_slug['disabled'], 'base_slug': 'disabled'})
    return result


def output_path(run_dir, pair):
    return (Path(run_dir) / 'judgments' / pair['agent'] / pair['scenario'] /
            f'{pair["config"]}--vs--{pair["base_slug"]}--r{pair["repeat"]}.json')


class Judge:
    """One judge model, called once per prompt with no tools."""

    def __init__(self, agent, scratch):
        self.agent = agent
        self.scratch = Path(scratch)
        if agent['client'] == 'codex':
            self.home = self.scratch / 'codex-home'
            self.home.mkdir(parents=True)
            auth = Path(clients.os.environ.get('CODEX_HOME', '~/.codex')).expanduser() / 'auth.json'
            (self.home / 'auth.json').symlink_to(auth)

    def ask(self, system, text):
        if self.agent['client'] == 'claude':
            command = ['claude', '-p', '--model', self.agent['model'], '--setting-sources', 'project,local',
                       '--tools', '', '--strict-mcp-config', '--no-session-persistence', '--output-format', 'json',
                       '--system-prompt', system]
            if self.agent['effort']:
                command += ['--effort', self.agent['effort']]
            result = subprocess.run(command, input=text, capture_output=True, text=True, cwd=self.scratch,
                                    env=clients.clean_env(), timeout=600)
            try:
                payload = json.loads(result.stdout)
            except ValueError:
                return None, None, result.stderr.strip() or result.stdout[-300:]
            return payload.get('result'), payload.get('total_cost_usd'), None
        with tempfile.NamedTemporaryFile('r', suffix='.txt', dir=self.scratch) as last:
            command = ['codex', 'exec', '--json', '--skip-git-repo-check', '--ephemeral', '-s', 'read-only',
                       '-m', self.agent['model'], '-o', last.name]
            if self.agent['effort']:
                command += ['-c', f'model_reasoning_effort={json.dumps(self.agent["effort"])}']
            result = subprocess.run(command + ['--', f'{system}\n\n{text}'], capture_output=True, text=True,
                                    cwd=self.scratch, stdin=subprocess.DEVNULL, timeout=600,
                                    env=clients.clean_env(CODEX_HOME=str(self.home)))
            turn = clients.parse_codex_turn([json.loads(line) for line in result.stdout.splitlines()
                                             if line.startswith('{')])
            usage = cost.tokens('codex', turn['usage'])
            spent = cost.price(cost.rates(cost.pricing(), self.agent), usage)
            return Path(last.name).read_text(encoding='utf-8') or turn['reply'], spent, turn['error']


def judge_pair(judge, pair, rubric, run_dir):
    variant_turns = report.read_json(pair['variant'] / 'turns.json')
    base_turns = report.read_json(pair['base'] / 'turns.json')
    system = system_prompt(rubric)
    orders = []
    for first_is_variant in (True, False):
        first, second = (variant_turns, base_turns) if first_is_variant else (base_turns, variant_turns)
        text, spent, error = judge.ask(system, prompt(pair['scenario'], rubric, first, second))
        parsed = parse(text)
        side = {'A': 'variant' if first_is_variant else 'base', 'B': 'base' if first_is_variant else 'variant'}
        orders.append({'variant_is': 'A' if first_is_variant else 'B', 'raw': text, 'error': error,
                       'cost_usd': spent, 'winner': side.get(parsed['winner'], 'tie') if parsed else None,
                       # A judge sometimes adds keys such as A_note; only the A and B scores count.
                       'scores': {side[key]: value for key, value in parsed['scores'].items() if key in side}
                       if parsed and isinstance(parsed.get('scores'), dict) else None,
                       'reason': parsed.get('reason') if parsed else None})
    winners = [order['winner'] for order in orders]
    verdict = winners[0] if winners[0] == winners[1] and winners[0] else ('unparsed' if None in winners else 'tie')
    record = {'judge': judge.agent, 'agent': pair['agent'], 'scenario': pair['scenario'], 'repeat': pair['repeat'],
              'variant': pair['config'], 'base': pair['base_slug'],
              'variant_path': str(pair['variant'].relative_to(run_dir)),
              'base_path': str(pair['base'].relative_to(run_dir)), 'verdict': verdict, 'orders': orders,
              'cost_usd': sum(order['cost_usd'] or 0 for order in orders)}
    path = output_path(run_dir, pair)
    path.parent.mkdir(parents=True, exist_ok=True)
    report.write_json(path, record)
    return record


def estimate(selected, rubric, judge_agent):
    """Calls, tokens and dollars for judging these pairs, from the size of each prompt."""
    system = system_prompt(rubric)
    input_tokens = 0
    for pair in selected:
        text = prompt(pair['scenario'], rubric, report.read_json(pair['variant'] / 'turns.json'),
                      report.read_json(pair['base'] / 'turns.json'))
        input_tokens += 2 * (len(system) + len(text)) // PROMPT_CHARS_PER_TOKEN
    counts = {'input': input_tokens, 'cache_write': 0, 'cache_read': 0, 'output': 2 * OUTPUT_TOKENS * len(selected)}
    return {'calls': 2 * len(selected), 'tokens': counts,
            'usd': cost.price(cost.rates(cost.pricing(), judge_agent), counts)}


def summary(run_dir):
    """judge.md: per scenario, each configuration's verdicts against what it was compared with."""
    records = [report.read_json(path) for path in sorted(Path(run_dir).glob('judgments/**/*.json'))]
    criteria = list(load_json('rubric.json')['criteria'])
    lines = ['# Judge verdicts', '',
             'Each row compares one variant with the base configuration, or the base with dialogue disabled, for the '
             'same agent, scenario and repeat. A verdict counts only when both orders agree; otherwise it is a tie. '
             'Score deltas are the variant minus what it was compared with, averaged over both orders. Each pair is '
             'in `judgments/`, with both replies\' paths and the judge\'s reasons.', '']
    by_config = {}
    for record in records:
        tally = by_config.setdefault((record['agent'], record['variant'], record['base']), {'variant': 0, 'base': 0,
                                                                                          'tie': 0, 'unparsed': 0})
        tally[record['verdict']] += 1
    lines += ['## Across scenarios', '', '| Agent | Variant | Against | Wins | Losses | Ties | Unparsed |',
              '| --- | --- | --- | --- | --- | --- | --- |']
    for (agent, variant, base), tally in sorted(by_config.items()):
        lines.append(f'| {agent} | `{variant}` | `{base}` | {tally["variant"]} | {tally["base"]} | {tally["tie"]} | '
                     f'{tally["unparsed"]} |')
    lines += ['', '## By scenario', '',
              '| Agent | Scenario | Variant | Against | Verdict | ' + ' | '.join(criteria) + ' |',
              '| --- | --- | --- | --- | --- | ' + ' | '.join('---' for _ in criteria) + ' |']
    for record in sorted(records, key=lambda item: (item['agent'], item['scenario'], item['variant'])):
        deltas = []
        for name in criteria:
            values = [order['scores']['variant'].get(name, 0) - order['scores']['base'].get(name, 0)
                      for order in record['orders'] if order['scores'] and 'variant' in order['scores']
                      and 'base' in order['scores']]
            deltas.append(f'{sum(values) / len(values):+.1f}' if values else '-')
        lines.append(f'| {record["agent"]} | {record["scenario"]} | `{record["variant"]}` | `{record["base"]}` | '
                     f'{record["verdict"]} | ' + ' | '.join(deltas) + ' |')
    (Path(run_dir) / 'judge.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(records)


def run(run_dir, base_slug, judge_agent, jobs, selected):
    rubric = load_json('rubric.json')
    lock = threading.Lock()
    done = {'count': 0, 'usd': 0.0}
    with tempfile.TemporaryDirectory(prefix='dialogue-testbed-judge-') as scratch:
        judge = Judge(judge_agent, scratch)

        def one(pair):
            record = judge_pair(judge, pair, rubric, run_dir)
            with lock:
                done['count'] += 1
                done['usd'] += record['cost_usd']
                print(f'[{done["count"]}/{len(selected)}] {record["verdict"]:<8} {pair["agent"]}/{pair["scenario"]}/'
                      f'{pair["config"]} vs {pair["base_slug"]}', flush=True)

        with ThreadPoolExecutor(max_workers=max(jobs, 1)) as pool:
            for future in [pool.submit(one, pair) for pair in selected]:
                future.result()
    summary(run_dir)
    return done['usd']

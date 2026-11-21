"""Did a reply follow the rules its policy turned on? Pass rates per rule, from the counts each turn already has.

A rule applies to a turn only when the variant's policy.md contains it and the scenario gives it a chance
to show. Every check is a pattern over the reply, so a rate is a pointer to transcripts, not a verdict.
"""

import csv
import json
from pathlib import Path
import re
import statistics

FRAMEWORK_FOR = {'escalation': 'sbar', 'handoff': 'ipass', 'status': 'can', 'safety': 'cus', 'incident': 'methane'}
VERDICT = re.compile(r'^\W*(?:\*\*)?(?:verdict:?\s*(?:\*\*)?:?\s*)?(?:no|yes|not|absent|implemented|broken|partly)\b',
                     re.IGNORECASE)


def guideline_names(run):
    """Guideline ID to the name the policy prints, from the plugin the run tested."""
    names = run.get('terms', {}).get('guidelines')
    if names:
        return names
    path = Path(run['plugin']['source']) / 'policy' / 'guidelines.json'
    return {entry['id']: entry['name'] for entry in json.loads(path.read_text(encoding='utf-8'))}


def checks(policy, names, scenario, number, template, reply, values):
    """(rule, passed) for every rule that applies to this turn."""
    on = lambda identifier: f'- {names.get(identifier, "?")}:' in policy
    threads = '## Thread protocol' in policy
    first = number == 1
    result = []
    if threads:
        result.append(('threads: no numbered list', values['numbered_items'] == 0))
        if values['thread_headings']:
            result.append(('threads: decisions under ### DECISIONS', values['decisions_heading']))
    if on('plain_punctuation'):
        result.append(('plain_punctuation: no em-dash', values['em_dashes'] == 0))
    if on('complete_grammar'):
        result.append(('complete_grammar: no contractions', values['contractions'] == 0))
    if on('short_sentences'):
        result.append(('short_sentences: none over 25 words', values['long_sentences'] == 0))
    if on('short_replies') and scenario == 'routine-question':
        result.append(('short_replies: at most 3 sentences', values['sentences'] <= 3))
    if on('tables') and scenario == 'compare' and first:
        result.append(('tables: a table for the comparison', values['tables'] >= 1))
    if on('verdict') and scenario == 'implemented' and first:
        result.append(('verdict: verdict first', bool(VERDICT.match(reply.strip()))))
    fixed = re.search(r'^## Situational framework: (\S+)', policy, re.MULTILINE)
    expected = FRAMEWORK_FOR.get(scenario)
    if first and fixed and expected:
        result.append((f'situation {fixed.group(1)}: its fields used', values['framework'].startswith(fixed.group(1))))
    if 'Situational mode: auto' in policy and first:
        if scenario == 'routine-question':
            result.append(('situation auto: no framework on a plain question', values['framework'] == ''))
        elif expected:
            result.append(('situation auto: the matching framework', values['framework'].startswith(expected)))
    if 'Acknowledgment is not acceptance' in policy and scenario == 'ownership':
        result.append(('signals full: a response status', any(
            marker.split('x')[0] in ('ACK', 'ACCEPTED', 'DONE', 'BLOCKED', 'NEED-INFO')
            for marker in values['markers'].split())))
    return result


def rows(run_dir, variants, run):
    names = guideline_names(run)
    result = []
    for case_dir, variant, metrics in variants:
        policy_path = case_dir / 'policy.md'
        policy = policy_path.read_text(encoding='utf-8') if policy_path.exists() else ''
        turns = json.loads((case_dir / 'turns.json').read_text(encoding='utf-8'))
        for number, (turn, values) in enumerate(zip(turns, metrics), 1):
            for rule, passed in checks(policy, names, variant['scenario']['id'], number, turn.get('template', ''),
                                       turn.get('reply') or '', values):
                result.append({'agent': variant['agent']['label'], 'scenario': variant['scenario']['id'],
                               'config': variant['slug'], 'repeat': variant['repeat'], 'turn': number,
                               'rule': rule, 'passed': passed,
                               'policy_unread': variant.get('policy_read') is False,
                               'path': str(case_dir.relative_to(run_dir))})
    return result


def noise(variants):
    """For every case run more than once: how much the counts move between repeats of one configuration."""
    groups = {}
    for _, variant, metrics in variants:
        key = (variant['agent']['label'], variant['scenario']['id'], variant['slug'])
        groups.setdefault(key, []).append(metrics)
    lines = []
    for (agent, scenario, config), runs in sorted(groups.items()):
        if len(runs) < 2:
            continue
        words = [sum(values['words'] for values in run) for run in runs]
        numbered = [sum(values['numbered_items'] for values in run) for run in runs]
        threads = [run[-1]['threads_open'] + run[-1]['threads_closed'] if run else 0 for run in runs]
        lines.append(f'| {agent} | {scenario} | `{config}` | {len(runs)} | {statistics.mean(words):.0f} '
                     f'± {statistics.stdev(words):.0f} | {min(numbered)} to {max(numbered)} | '
                     f'{min(threads)} to {max(threads)} |')
    if not lines:
        return []
    return ['## Spread between repeats', '',
            'A difference between configurations smaller than this spread is noise. Words are summed over turns.', '',
            '| Agent | Scenario | Config | Repeats | Words, mean ± sd | Numbered items | Threads |',
            '| --- | --- | --- | --- | --- | --- | --- |', *lines, '']


def write(run_dir, variants, run):
    """compliance.csv: one row per rule checked on a turn. compliance.md: pass rates, and the spread between repeats."""
    run_dir = Path(run_dir)
    found = rows(run_dir, variants, run)
    if found:
        with open(run_dir / 'compliance.csv', 'w', newline='', encoding='utf-8') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(found[0]))
            writer.writeheader()
            writer.writerows(found)
    agents = sorted({row['agent'] for row in found})
    lines = ['# Rule compliance', '',
             'Each cell is turns that passed / turns the rule applied to. Claude variants that saw only the preview of '
             'an over-limit policy are left out of the rates and counted in the last column. One row per check is in '
             '`compliance.csv`, with the path of its variant.', '',
             '| Rule | ' + ' | '.join(agents) + ' | Left out, preview unread |',
             '| --- | ' + ' | '.join('---' for _ in agents) + ' | --- |']
    for rule in sorted({row['rule'] for row in found}):
        cells = []
        for agent in agents:
            subset = [row for row in found if row['rule'] == rule and row['agent'] == agent and not row['policy_unread']]
            passed = sum(row['passed'] for row in subset)
            cells.append(f'{passed}/{len(subset)} ({passed / len(subset):.0%})' if subset else '-')
        left_out = sum(row['policy_unread'] for row in found if row['rule'] == rule)
        lines.append(f'| {rule} | ' + ' | '.join(cells) + f' | {left_out} |')
    if not found:
        lines.append('| no rule applied | | |')
    lines += ['', *noise(variants)]
    (run_dir / 'compliance.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(found)

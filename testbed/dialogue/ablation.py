"""What removing one rule changes: each unit of a leave-one-out suite against its reference.

A unit is a configuration named `REF.-GUIDELINE` or `REF.~FILELINE`, or `REF.*together` for several units removed
at once; its reference is the configuration named REF. For every agent and scenario, the reference's repeats give a range, a mean and a spread for each count. A
unit's count changed when its values and the reference's do not overlap, and its mean moved by at least one and
by more than twice that spread. A unit with no changed
count, no changed compliance rate and no judge losses has no measurable effect: the text it removes costs
tokens and buys nothing these scenarios can see.
"""

import csv
import json
from pathlib import Path
import re
import statistics

import compliance

COUNTS = ('words', 'sentences', 'long_sentences', 'bullets', 'numbered_items', 'tables', 'headings', 'em_dashes',
          'contractions', 'thread_headings', 'option_lines', 'recommended', 'narration_blocks', 'tool_calls',
          'dialogue_calls')
FLAGS = ('decisions_heading', 'footer')
UNIT = re.compile(r'^(?P<ref>[^.]+)\.(?P<kind>[-~*])(?P<what>.+)$')
KINDS = {'-': 'guideline', '~': 'line', '*': 'together'}


def totals(metrics, state_threads):
    """One case's counts, summed over its turns."""
    values = {key: sum(turn[key] for turn in metrics) for key in COUNTS}
    values.update({key: sum(bool(turn[key]) for turn in metrics) for key in FLAGS})
    values['framework'] = sum(bool(turn['framework']) for turn in metrics)
    values['markers'] = sum(len(turn['markers'].split()) for turn in metrics)
    values['threads'] = state_threads
    return values


def write(run_dir, variants, run):
    run_dir = Path(run_dir)
    cases = {}
    for case_dir, variant, metrics in variants:
        last = metrics[-1] if metrics else {}
        # A case that failed part way would count as a change, so only complete cases are compared.
        complete = metrics and variant['status'] == 'complete'
        values = totals(metrics, last.get('threads_open', 0) + last.get('threads_closed', 0)) if complete else None
        cases.setdefault((variant['agent']['label'], variant['slug']), {}).setdefault(
            variant['scenario']['id'], []).append({'values': values, 'chars': variant['policy_chars'],
                                                  'variant': variant})
    units = sorted({(agent, slug) for agent, slug in cases if UNIT.match(slug)})
    if not units:
        return 0
    checks = compliance.rows(run_dir, variants, run)
    rates = {}
    for row in checks:
        entry = rates.setdefault((row['agent'], row['config'], row['rule']), [0, 0])
        entry[0] += row['passed']
        entry[1] += 1
    verdicts = {}
    for path in sorted(run_dir.glob('judgments/**/*.json')):
        record = json.loads(path.read_text(encoding='utf-8'))
        tally = verdicts.setdefault((record['agent'], record['variant'], record['base']),
                                    {'variant': 0, 'base': 0, 'tie': 0, 'unparsed': 0})
        tally[record['verdict']] += 1
    rows = []
    for agent, unit in units:
        match = UNIT.match(unit)
        reference = cases.get((agent, match['ref']))
        if not reference:
            continue
        changed = []
        for scenario, runs in sorted(cases[(agent, unit)].items()):
            base_runs = [item['values'] for item in reference.get(scenario, []) if item['values']]
            unit_runs = [item['values'] for item in runs if item['values']]
            if len(base_runs) < 2 or not unit_runs:
                continue
            for key in (*COUNTS, *FLAGS, 'framework', 'markers', 'threads'):
                base_values = [values[key] for values in base_runs]
                unit_values = [values[key] for values in unit_runs]
                moved = statistics.mean(unit_values) - statistics.mean(base_values)
                apart = min(unit_values) > max(base_values) or max(unit_values) < min(base_values)
                if apart and abs(moved) >= 1 and abs(moved) > 2 * statistics.stdev(base_values):
                    changed.append(f'{scenario} {key} {moved:+.0f}')
        rules = []
        for (rule_agent, config, rule), (passed, total) in rates.items():
            if rule_agent == agent and config == unit:
                base_passed, base_total = rates.get((agent, match['ref'], rule), (0, 0))
                if base_total and abs(passed / total - base_passed / base_total) >= 0.25:
                    rules.append(f'{rule}: {base_passed / base_total:.0%} to {passed / total:.0%}')
        tally = verdicts.get((agent, unit, match['ref']))
        sample = next(iter(cases[(agent, unit)].values()))[0]
        reference_chars = next(iter(reference.values()))[0]['chars']
        config = sample['variant']['config']
        removed = {'-': match['what'], '~': (config.get('drops_text') or [''])[0],
                   '*': ', '.join(config.get('together', []))}[match['kind']]
        # A line unit saves its own text; the others save what their policy no longer prints.
        saved = len(removed) + 1 if match['kind'] == '~' else reference_chars - sample['chars']
        rows.append({
            'agent': agent, 'unit': unit, 'kind': KINDS[match['kind']],
            'removed': removed,
            'chars_saved': saved,
            'counts_changed': '; '.join(changed), 'compliance_changed': '; '.join(rules),
            'judge': f'{tally["variant"]} won, {tally["base"]} lost, {tally["tie"]} tied' if tally else '',
            'effect': 'yes' if changed or rules or (tally and tally['base']) else 'none measured',
        })
    with open(run_dir / 'ablation.csv', 'w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ['# Ablation: one rule removed at a time', '',
             'Each row removes one guideline, or one rule line, from the reference configuration. A count changed '
             'when the unit\'s values and the reference\'s do not overlap across repeats, and the mean moved by '
             'at least one and by more than twice the reference\'s spread. With three repeats and about twenty '
             'counts per scenario, expect some changes by chance; read the transcripts behind a single change. '
             'Compliance changed when a rule\'s pass rate moved 25 points or more. Judge verdicts appear after '
             '`testbed.py judge RUN --against ref`; a loss means the reference was better.', '']
    for agent in sorted({row['agent'] for row in rows}):
        subset = [row for row in rows if row['agent'] == agent]
        single = [row for row in subset if row['kind'] != 'together']
        quiet = [row for row in single if row['effect'] == 'none measured']
        lines += [f'## {agent}', '',
                  f'{len(quiet)} of {len(single)} units show no measurable effect; together they are '
                  f'{sum(row["chars_saved"] for row in quiet):,} characters of policy. A `together` row removes '
                  'every unit run in that row at once: an effect there means some of them matter only in pairs.', '',
                  '| Unit | Removes | Characters | Counts changed | Compliance changed | Judge | Effect |',
                  '| --- | --- | --- | --- | --- | --- | --- |']
        for row in sorted(subset, key=lambda item: (item['effect'] != 'none measured', -item['chars_saved'])):
            removed = row['removed'].replace('|', '\\|')
            removed = removed if row['kind'] == 'together' else removed[:90]
            lines.append(f'| `{row["unit"]}` | {removed} | {row["chars_saved"]} | {row["counts_changed"] or "-"} | '
                         f'{row["compliance_changed"] or "-"} | {row["judge"] or "-"} | {row["effect"]} |')
        lines.append('')
    (run_dir / 'ablation.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(rows)

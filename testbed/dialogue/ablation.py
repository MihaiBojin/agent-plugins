"""What removing a rule changes: each unit of a leave-one-out suite against every other configuration.

A unit is a configuration named `REF.-GUIDELINE` or `REF.~FILELINE` for one rule, or `REF.*NAME` for several removed
at once; its reference is the configuration named REF. Most units change nothing, so the null is all of them:
for each agent, scenario and count, a unit's mean is compared with the median of the other configurations' means, scaled
by the spread between repeats pooled over all configurations. A unit's score is its largest such z over every
scenario and count. Shuffling the configuration labels within each scenario gives the scores noise alone
produces; a unit's p-value is the share of shuffles in which its label scores as high. A unit has an effect when
it passes the Benjamini-Hochberg cut at a 10% false discovery rate across the agent's units.
"""

import bisect
import csv
import json
import math
from pathlib import Path
import random
import re

import compliance

COUNTS = ('words', 'sentences', 'long_sentences', 'bullets', 'numbered_items', 'tables', 'headings', 'em_dashes',
          'contractions', 'latin_abbreviations', 'unexpanded_acronyms', 'bare_demonstratives', 'long_paragraphs',
          'lists_without_lead_in', 'nested_items',
          'thread_headings', 'option_lines', 'recommended', 'narration_blocks', 'tool_calls',
          'dialogue_calls')
FLAGS = ('decisions_heading', 'footer')
UNIT = re.compile(r'^(?P<ref>[^.]+)\.(?P<kind>[-~*])(?P<what>.+)$')
KINDS = {'-': 'guideline', '~': 'line', '*': 'group'}
SHUFFLES = 1000
FALSE_DISCOVERY = 0.10
SHOWN_Z = 3.0


def totals(metrics, state_threads):
    """One case's counts, summed over its turns."""
    values = {key: sum(turn[key] for turn in metrics) for key in COUNTS}
    values.update({key: sum(bool(turn[key]) for turn in metrics) for key in FLAGS})
    values['framework'] = sum(bool(turn['framework']) for turn in metrics)
    values['markers'] = sum(len(turn['markers'].split()) for turn in metrics)
    values['threads'] = state_threads
    return values


def median_without(ordered, value):
    """The median of a sorted list with one occurrence of value taken out."""
    index = bisect.bisect_left(ordered, value)
    rest = len(ordered) - 1

    def at(position):
        return ordered[position] if position < index else ordered[position + 1]

    return at(rest // 2) if rest % 2 else (at(rest // 2 - 1) + at(rest // 2)) / 2


def scores(rows):
    """For rows of (config, values) from one scenario: config -> [(metric, z, moved)] for every count that varies.

    A configuration's move is its mean less the median of the other configurations' means, so one unit with a
    large effect does not shift every other unit's comparison.

    A session without a metric is left out of it: a compliance check runs only where the policy has its rule, so
    a unit that removes the rule has no value for that check rather than a failing one."""
    groups = {}
    for config, values in rows:
        groups.setdefault(config, []).append(values)
    result = {config: [] for config in groups}
    for metric in sorted({key for _, values in rows for key in values}):
        measured = {config: [item[metric] for item in items if metric in item] for config, items in groups.items()}
        measured = {config: xs for config, xs in measured.items() if xs}
        if len(measured) < 3:
            continue
        means = {config: sum(xs) / len(xs) for config, xs in measured.items()}
        variances = [sum((x - means[config]) ** 2 for x in xs) / (len(xs) - 1)
                     for config, xs in measured.items() if len(xs) > 1]
        spread = math.sqrt(sum(variances) / len(variances)) if variances else 0.0
        if not spread:
            if max(means.values()) == min(means.values()):
                continue
            # No session differs from its configuration's others, yet the configurations differ, as when a check
            # always passes except where its rule is gone: a floor keeps that z finite and large.
            spread = 0.5 / math.sqrt(sum(len(xs) for xs in measured.values()))
        ordered, others = sorted(means.values()), len(means) - 1
        repeats = sum(len(xs) for xs in measured.values()) / len(measured)
        for config, mean in means.items():
            moved = mean - median_without(ordered, mean)
            z = moved / (spread * math.sqrt(1 / len(measured[config]) + 1 / (others * repeats)))
            result[config].append((metric, z, moved))
    return {config: tests for config, tests in result.items() if tests}


def top(by_scenario):
    """Each configuration's score: its largest |z| over every scenario and count."""
    best = {}
    for scenario, rows in by_scenario.items():
        for config, tests in scores(rows).items():
            for _, z, _ in tests:
                best[config] = max(best.get(config, 0.0), abs(z))
    return best


def p_values(by_scenario, units, shuffles=SHUFFLES, seed=7):
    """unit -> share of label shuffles in which the unit's label scores at least as high as it does."""
    rng = random.Random(seed)
    real = top(by_scenario)
    beaten = {unit: 0 for unit in units}
    for _ in range(shuffles):
        mixed = {}
        for scenario, rows in by_scenario.items():
            labels = [config for config, _ in rows]
            rng.shuffle(labels)
            mixed[scenario] = [(label, values) for label, (_, values) in zip(labels, rows)]
        noise = top(mixed)
        for unit in units:
            beaten[unit] += noise.get(unit, 0.0) >= real.get(unit, 0.0)
    return {unit: (1 + beaten[unit]) / (1 + shuffles) for unit in units}


def discoveries(p, rate=FALSE_DISCOVERY):
    """The units that pass the Benjamini-Hochberg cut."""
    ranked = sorted(p, key=p.get)
    passed = 0
    for rank, unit in enumerate(ranked, 1):
        if p[unit] <= rate * rank / len(ranked):
            passed = rank
    return set(ranked[:passed])


def write(run_dir, variants, run):
    run_dir = Path(run_dir)
    checks = compliance.rows(run_dir, variants, run)
    rates = {}  # case path -> rule -> passed, one per turn
    for row in checks:
        rates.setdefault(row['path'], {}).setdefault(row['rule'], []).append(row['passed'])
    sessions = {}  # agent -> scenario -> [(config, values)]
    chars = {}
    together = {}
    for case_dir, variant, metrics in variants:
        agent, unit = variant['agent']['label'], variant['slug']
        chars.setdefault((agent, unit), variant['policy_chars'])
        together.setdefault(unit, variant['config'])
        # A case that failed part way would count as a change, so only complete cases are compared.
        if not metrics or variant['status'] != 'complete':
            continue
        last = metrics[-1]
        values = {key: float(value) for key, value in
                  totals(metrics, last.get('threads_open', 0) + last.get('threads_closed', 0)).items()}
        for rule, passed in rates.get(str(case_dir.relative_to(run_dir)), {}).items():
            values[f'rule: {rule}'] = sum(passed) / len(passed)
        sessions.setdefault(agent, {}).setdefault(variant['scenario']['id'], []).append((unit, values))
    verdicts = {}
    for path in sorted(run_dir.glob('judgments/**/*.json')):
        record = json.loads(path.read_text(encoding='utf-8'))
        tally = verdicts.setdefault((record['agent'], record['variant'], record['base']),
                                    {'variant': 0, 'base': 0, 'tie': 0, 'unparsed': 0})
        tally[record['verdict']] += 1
    rows = []
    for agent, by_scenario in sorted(sessions.items()):
        units = sorted({config for rows_ in by_scenario.values() for config, _ in rows_ if UNIT.match(config)})
        if not units:
            continue
        p = p_values(by_scenario, units)
        found = discoveries(p)
        tests = {}
        for scenario, scenario_rows in by_scenario.items():
            for config, results in scores(scenario_rows).items():
                tests.setdefault(config, []).extend((scenario, metric, z, moved) for metric, z, moved in results)
        for unit in units:
            match = UNIT.match(unit)
            config = together[unit]
            removed = {'-': match['what'], '~': (config.get('drops_text') or [''])[0],
                       '*': ', '.join(config.get('together', []))}[match['kind']]
            reference_chars = chars.get((agent, match['ref']))
            # A line unit saves its own text; the others save what their policy no longer prints.
            saved = len(removed) + 1 if match['kind'] == '~' else (reference_chars or 0) - chars[(agent, unit)]
            strongest = sorted((test for test in tests.get(unit, []) if abs(test[2]) >= SHOWN_Z),
                               key=lambda test: -abs(test[2]))[:4]
            tally = verdicts.get((agent, unit, match['ref']))
            rows.append({
                'agent': agent, 'unit': unit, 'kind': KINDS[match['kind']], 'removed': removed,
                'chars_saved': saved, 'p': round(p[unit], 4),
                'strongest': '; '.join(f'{scenario} {metric} {moved:+.1f} (z {z:+.1f})'
                                       for scenario, metric, z, moved in strongest),
                'judge': f'{tally["variant"]} won, {tally["base"]} lost, {tally["tie"]} tied' if tally else '',
                'effect': 'yes' if unit in found else 'none measured',
            })
    if not rows:
        return 0
    with open(run_dir / 'ablation.csv', 'w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ['# Ablation: rules removed', '',
             f'Each row removes one guideline, one rule line, or a group of them from the reference configuration. '
             f'`p` is the share of {SHUFFLES:,} label shuffles in which noise scores as high as the unit; a unit has '
             f'an effect when it passes the Benjamini-Hochberg cut at a {FALSE_DISCOVERY:.0%} false discovery rate. '
             f'Counts include each compliance rule\'s pass rate. The strongest column lists counts with |z| of '
             f'{SHOWN_Z:g} or more: the move against the other configurations\' mean, per session. Judge verdicts '
             'appear after `testbed.py judge RUN --against ref`; they do not decide the effect column.', '']
    for agent in sorted({row['agent'] for row in rows}):
        subset = [row for row in rows if row['agent'] == agent]
        quiet = [row for row in subset if row['effect'] == 'none measured']
        lines += [f'## {agent}', '',
                  f'{len(quiet)} of {len(subset)} units show no measurable effect; together they are '
                  f'{sum(row["chars_saved"] for row in quiet):,} characters of policy. A group or `together` row '
                  'removes all its members at once: an effect there means some of them matter, alone or in pairs.',
                  '', '| Unit | Removes | Characters | p | Strongest counts | Judge | Effect |',
                  '| --- | --- | --- | --- | --- | --- | --- |']
        for row in sorted(subset, key=lambda item: (item['effect'] != 'yes', item['p'], -item['chars_saved'])):
            removed = row['removed'].replace('|', '\\|')
            removed = removed if row['kind'] == 'group' else removed[:90]
            lines.append(f'| `{row["unit"]}` | {removed} | {row["chars_saved"]} | {row["p"]:.3f} | '
                         f'{row["strongest"] or "-"} | {row["judge"] or "-"} | {row["effect"]} |')
        lines.append('')
    (run_dir / 'ablation.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(rows)

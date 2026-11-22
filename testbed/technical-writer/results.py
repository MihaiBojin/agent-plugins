"""bench.csv and bench.md for a run: what each configuration wrote, how simple it reads, and which rules it followed.

A unit is a configuration that removes rules: `-ID` for one rule, `*NAME` for a group or a section. Its effect
comes from the dialogue testbed's ablation statistics: every configuration except `off` is the null, each task is
a scenario, and the metrics and the judge's verdicts are the counts.
"""

import csv
import json
from pathlib import Path

import ablation
import skill

SHOWN = ('words', 'words_per_sentence', 'chars_per_word', 'long_words_pct', 'grade')


def sessions(run_dir):
    """Every complete case as (record, values): the measures, `rule: ID` verdicts and `skill_fired`."""
    found = []
    for path in sorted(Path(run_dir).glob('cases/*/*/*/r*/case.json')):
        record = json.loads(path.read_text(encoding='utf-8'))
        if record['status'] != 'complete':
            continue
        values = {key: float(value) for key, value in
                  json.loads((path.parent / 'metrics.json').read_text(encoding='utf-8')).items()}
        verdicts = json.loads((path.parent / 'grades.json').read_text(encoding='utf-8'))['verdicts']
        values.update({f'rule: {identifier}': value for identifier, value in verdicts.items()})
        values['skill_fired'] = float(bool(record['skill_fired']))
        found.append((record, values))
    return found


def mean(values):
    return sum(values) / len(values) if values else None


def order(config):
    return ({'off': 0, 'full': 1}.get(config, 2), config)


def without(config_names, rule, groups):
    """The configuration that removes a rule: its own unit if the run has one, else its group's."""
    if f'-{rule}' in config_names:
        return f'-{rule}'
    return next((f'*{name}' for name, members in groups.items() if rule in members and f'*{name}' in config_names),
                None)


def write(run_dir, rules):
    run_dir = Path(run_dir)
    found = sessions(run_dir)
    ids = [rule['id'] for rule in rules]
    with open(run_dir / 'bench.csv', 'w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        metric_names = list(found[0][1]) if found else []
        writer.writerow(['agent', 'task', 'config', 'repeat', 'skill_chars', 'cost_usd', *metric_names])
        for record, values in found:
            writer.writerow([record['agent']['label'], record['task'], record['config'], record['repeat'],
                             record['skill_chars'], record['cost_usd'], *[values.get(name, '') for name in metric_names]])
    lines = ['# technical-writer benchmark', '',
             '`off` runs without the plugin and `full` with all of it; `-ID` removes one rule and `*NAME` a group of '
             'rules or a section. Words, sentence length, word length, the share of words of three syllables or '
             'more, and the Flesch-Kincaid grade measure how simple a document reads; lower is simpler. Rules '
             'passed is the share of rules the judge found followed, of those that apply. A unit has an effect '
             'when it passes the Benjamini-Hochberg cut at 10% against every configuration but `off`, over '
             f'{ablation.SHUFFLES:,} label shuffles.', '']
    groups = skill.groups()
    for agent in sorted({record['agent']['label'] for record, _ in found}):
        mine = [(record, values) for record, values in found if record['agent']['label'] == agent]
        configs = sorted({record['config'] for record, _ in mine}, key=order)
        lines += [f'## {agent}', '', '| Configuration | Sessions | Skill loaded | Words | Words per sentence | '
                  'Characters per word | Long words % | Grade | Rules passed % | Skill characters |',
                  '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |']
        for config in configs:
            rows = [(record, values) for record, values in mine if record['config'] == config]
            passed = [value for _, values in rows for key, value in values.items() if key.startswith('rule: ')]
            shown = [f'{mean([values[name] for _, values in rows]):.1f}' for name in SHOWN]
            chars = rows[0][0]['skill_chars']
            rate = f'{100 * mean(passed):.0f}' if passed else '-'
            lines.append(f'| `{config}` | {len(rows)} | {mean([v["skill_fired"] for _, v in rows]):.0%} | '
                         f'{" | ".join(shown)} | {rate} | {chars if chars is not None else "-"} |')
        lines += ['', '| Rule | Passed, off | Passed, full | Passed without it | Without it |',
                  '| --- | --- | --- | --- | --- |']
        for identifier in ids:
            key = f'rule: {identifier}'

            def rate(config):
                judged = [values[key] for record, values in mine if record['config'] == config and key in values]
                return f'{mean(judged):.0%} of {len(judged)}' if judged else '-'

            unit = without(configs, identifier, groups)
            lines.append(f'| `{identifier}` | {rate("off")} | {rate("full")} | {rate(unit) if unit else "-"} | '
                         f'{f"`{unit}`" if unit else "-"} |')
        by_task = {}
        for record, values in mine:
            if record['config'] != 'off':
                by_task.setdefault(record['task'], []).append((record['config'], values))
        units = [config for config in configs if config[0] in '-*']
        if units:
            p = ablation.p_values(by_task, units)
            found_effects = ablation.discoveries(p)
            tests = {}
            for task, rows in by_task.items():
                for config, results in ablation.scores(rows).items():
                    tests.setdefault(config, []).extend((task, metric, z, moved) for metric, z, moved in results)
            lines += ['', '| Unit | p | Strongest moves against the other configurations | Effect |',
                      '| --- | --- | --- | --- |']
            for unit in sorted(units, key=lambda name: (name not in found_effects, p[name])):
                strongest = sorted((test for test in tests.get(unit, []) if abs(test[2]) >= ablation.SHOWN_Z),
                                   key=lambda test: -abs(test[2]))[:4]
                moves = '; '.join(f'{task} {metric} {moved:+.2f} (z {z:+.1f})' for task, metric, z, moved in strongest)
                lines.append(f'| `{unit}` | {p[unit]:.3f} | {moves or "-"} | '
                             f'{"yes" if unit in found_effects else "none measured"} |')
        lines.append('')
    (run_dir / 'bench.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(found)

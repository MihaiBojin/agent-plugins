"""The benchmark's deterministic parts: the skill's rules and groups, plugin copies, measures, grades and the report."""

import json
from pathlib import Path
import random
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / 'dialogue'))
sys.dont_write_bytecode = True

import bench  # noqa: E402
import grade  # noqa: E402
import measure  # noqa: E402
import results  # noqa: E402
import skill  # noqa: E402

PLUGIN = bench.DEFAULT_PLUGIN


class SkillTest(unittest.TestCase):
    def test_every_rule_is_in_exactly_one_group(self):
        ids = [rule['id'] for rule in skill.rules(PLUGIN)]
        members = [member for group in skill.groups().values() for member in group]
        self.assertEqual(sorted(members), sorted(ids))
        self.assertEqual(len(members), len(set(members)))

    def test_a_rule_spans_its_heading_up_to_the_next_heading(self):
        rules = {rule['id']: rule for rule in skill.rules(PLUGIN)}
        lines = skill.lines_of(PLUGIN)
        bluf = rules['bluf']
        self.assertEqual(lines[bluf['start']].strip(), '### `bluf`')
        self.assertTrue(lines[bluf['end']].startswith('#'))
        self.assertEqual(bluf['section'], 'Shared rules')
        self.assertEqual(rules['self_edit']['section'], 'Document rules')

    def test_a_copy_drops_only_the_removed_rules(self):
        units = skill.units(PLUGIN, 'all')
        self.assertIsNone(units['off'])
        self.assertEqual(units['full'], [])
        with tempfile.TemporaryDirectory() as root:
            copy = skill.patched(PLUGIN, units['*language'], Path(root) / 'copy')
            text = (copy / skill.SKILL).read_text(encoding='utf-8')
            self.assertNotIn('### `short_sentences`', text)
            self.assertIn('### `bluf`', text)
            self.assertFalse((copy / 'evals').exists())
            self.assertEqual(len(skill.rules(copy)), len(skill.rules(PLUGIN)) - len(skill.groups()['language']))

    def test_every_task_has_a_prompt(self):
        found = bench.tasks(PLUGIN)
        self.assertGreaterEqual(len(found), 6)
        for task in found:
            self.assertTrue(task['prompt'])
            self.assertFalse(task['prompt'].startswith('---'))

    def test_plugin_configurations_ask_for_the_prose_skill(self):
        task = {'prompt': 'Write a runbook.'}
        self.assertEqual(bench.prompt_for({'task': task, 'spans': []}),
                         'Use the write-technical-prose skill.\n\nWrite a runbook.')
        self.assertEqual(bench.prompt_for({'task': task, 'spans': None}), task['prompt'])

    def test_detects_only_successful_loads_of_the_prose_skill(self):
        plugin = '/cache/technical-writer/0.4.0/skills'
        prose = f'{plugin}/write-technical-prose/SKILL.md'
        readme = f'{plugin}/write-project-readme/SKILL.md'
        for name, arguments, error, expected in [
                ('Skill', {'skill': 'write-technical-prose'}, False, True),
                ('Skill', {'skill': 'technical-writer:write-technical-prose'}, False, True),
                ('Skill', {'skill': 'technical-writer:write-pr-description'}, False, False),
                ('Skill', {'skill': 'other:write-technical-prose'}, False, False),
                ('Skill', {'skill': 'technical-writer:audit-project-readme', 'args': prose}, False, False),
                ('shell', f"/bin/zsh -lc 'cat {prose}'", False, True),
                ('shell', f"cat {readme}", False, False),
                ('shell', f"cat {prose}.bak", False, False),
                ('shell', f"ls {prose}", False, False),
                ('shell', f"cat {readme} && ls {prose}", False, False),
                ('shell', f"cat {prose}", True, False),
                ('Read', {'file_path': prose}, False, True),
                ('Grep', {'pattern': prose}, False, False)]:
            with self.subTest(name=name, arguments=arguments, error=error):
                item = {'type': 'tool', 'name': name, 'input': arguments, 'is_error': error}
                self.assertEqual(bench.fired([item]), expected)

    def test_cases_cover_each_configuration_task_and_repeat(self):
        agents = [bench.matrix.parse_agent('claude:haiku')]
        selected = bench.cases(PLUGIN, agents, 'groups', 2, task_ids=['runbook'])
        configs = {case['config'] for case in selected}
        self.assertEqual(configs, {'off', 'full', *(f'*{name}' for name in skill.groups()), '*dials'})
        self.assertEqual(len(selected), 2 * len(configs))


class MeasureTest(unittest.TestCase):
    def test_simple_text_scores_lower_than_dense_text(self):
        simple = measure.measure('Stop the job. Check the log. Run it again.')
        dense = measure.measure('The comprehensive organizational reconfiguration necessitated considerable '
                                'administrative documentation, notwithstanding substantial interdepartmental '
                                'opposition.')
        self.assertLess(simple['words_per_sentence'], dense['words_per_sentence'])
        self.assertLess(simple['chars_per_word'], dense['chars_per_word'])
        self.assertLess(simple['long_words_pct'], dense['long_words_pct'])
        self.assertLess(simple['grade'], dense['grade'])

    def test_code_does_not_count_as_prose(self):
        values = measure.measure('Run `pgctl promote orders-db-2`.\n\n```sh\nfeaturectl set orders.read_only true\n```\n')
        self.assertEqual(values['words'], 1)

    def test_marks(self):
        values = measure.measure("# Title\n\n- It's done — mostly.\n1. The file was deleted.\n")
        self.assertEqual((values['headings'], values['bullets'], values['numbered_items']), (1, 1, 1))
        self.assertEqual((values['em_dashes'], values['contractions'], values['passive']), (1, 1, 1))


class GradeTest(unittest.TestCase):
    def test_parse_keeps_pass_and_fail_and_drops_the_rest(self):
        text = ('Here: {"bluf": "pass", "tables": "FAIL: two options compared in prose", "warnings": "na", '
                '"extra": "pass"}')
        self.assertEqual(grade.parse(text, ['bluf', 'tables', 'warnings', 'missing']), {'bluf': 1.0, 'tables': 0.0})
        self.assertEqual(grade.reasons(text), {'tables': 'two options compared in prose'})
        self.assertIsNone(grade.parse('no json', ['bluf']))

    def test_prompt_lists_every_rule_with_its_text(self):
        rules = skill.rules(PLUGIN)
        text = grade.prompt('Write a runbook.', rules, '# Runbook')
        for rule in rules:
            self.assertIn(f'### `{rule["id"]}`', text)
        self.assertIn('<document>\n# Runbook\n</document>', text)


class ResultsTest(unittest.TestCase):
    def write_case(self, root, config, repeat, values, verdicts):
        case_dir = Path(root) / 'cases' / 'claude-haiku' / 'runbook' / config / f'r{repeat}'
        case_dir.mkdir(parents=True)
        record = {'agent': {'label': 'claude-haiku'}, 'task': 'runbook', 'config': config, 'repeat': repeat,
                  'status': 'complete', 'skill_fired': config != 'off', 'skill_chars': None if config == 'off' else 1,
                  'cost_usd': 0.0}
        (case_dir / 'case.json').write_text(json.dumps(record), encoding='utf-8')
        (case_dir / 'metrics.json').write_text(json.dumps(values), encoding='utf-8')
        (case_dir / 'grades.json').write_text(json.dumps({'verdicts': verdicts}), encoding='utf-8')

    def test_report_finds_the_unit_whose_own_rule_breaks(self):
        rng = random.Random(3)
        rules = [rule for rule in skill.rules(PLUGIN) if rule['id'] in ('bluf', 'warnings')]
        with tempfile.TemporaryDirectory() as root:
            for config in ['off', 'full', '*risk'] + [f'*quiet{n}' for n in range(8)]:
                for repeat in range(1, 7):
                    warned = config != '*risk' or rng.random() < 0.1
                    self.write_case(root, config, repeat, {name: rng.gauss(30, 3) for name in results.SHOWN},
                                    {'bluf': float(rng.random() < 0.8), 'warnings': float(warned)})
            self.assertEqual(results.write(root, rules), 66)
            report = (Path(root) / 'bench.md').read_text(encoding='utf-8')
        self.assertIn('| `*risk` |', report)
        risk_row = next(line for line in report.splitlines() if line.startswith('| `*risk` | 0.'))
        self.assertTrue(risk_row.endswith('| yes |'), risk_row)
        self.assertIn('| `warnings` | 100% of 6 | 100% of 6 |', report)


if __name__ == '__main__':
    unittest.main()

"""The testbed's deterministic parts: the matrix, placeholders, parsing, metrics, cost and rendering."""

import json
import random
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import ablation  # noqa: E402
import clients  # noqa: E402
import compliance  # noqa: E402
import cost  # noqa: E402
import judge  # noqa: E402
import matrix  # noqa: E402
import metrics  # noqa: E402
import plugin  # noqa: E402
import report  # noqa: E402
import runner  # noqa: E402

PLUGIN = HERE.parents[1] / 'plugins' / 'dialogue'
CLAUDE = matrix.parse_agent('claude:haiku')
CODEX = matrix.parse_agent('codex:gpt-6-luna:low')


class MatrixTest(unittest.TestCase):
    def setUp(self):
        self.values = matrix.catalog(PLUGIN)
        self.base = plugin.fresh_defaults(PLUGIN)

    def test_base_is_what_enable_gives_a_fresh_session(self):
        self.assertEqual(self.base, {'enabled': True, 'comms': 'pyramid', 'style': 'plain', 'situation': 'none',
                                     'signals': 'off', 'threads': 'focus-compact', 'guidelines': {}})

    def test_full_product_has_a_unique_slug_per_configuration(self):
        configs = list(matrix.product(self.base, self.values))
        expected = 1
        for key in matrix.DIMENSIONS:
            expected *= len(self.values[key])
        self.assertEqual(len(configs), expected)
        self.assertEqual(len({matrix.slug(config) for config in configs}), expected)

    def test_default_plan_runs_each_case_once_and_names_known_scenarios(self):
        suites = matrix.load_json('suites.json')['default']
        cases = matrix.cases(PLUGIN, self.base, [CLAUDE, CODEX], suites)
        keys = [case['key'] for case in cases]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual(sum(case['agent'] is CLAUDE for case in cases), len(cases) / 2)
        base_slug = matrix.slug(self.base)
        compare = [case for case in cases if case['agent'] is CLAUDE and case['scenario']['id'] == 'compare'
                   and matrix.slug(case['config']) == base_slug]
        self.assertEqual(len(compare), 1)
        self.assertEqual(compare[0]['suites'], ['baseline', 'comms', 'style', 'threads'])

    def test_full_suite_adds_every_combination(self):
        cases = matrix.cases(PLUGIN, self.base, [CLAUDE], ['full'], scenario_ids=['implemented'])
        self.assertEqual(len(cases), len(list(matrix.product(self.base, self.values))) + 1)

    def test_filters_and_limit_apply_to_every_agent_alike(self):
        cases = matrix.cases(PLUGIN, self.base, [CLAUDE, CODEX], ['style'], config_match=['.ste.'], limit=2)
        self.assertEqual([case['agent']['client'] for case in cases], ['claude', 'claude', 'codex', 'codex'])
        self.assertTrue(all('.ste.' in case['key'] for case in cases))

    def test_unknown_values_are_rejected(self):
        with self.assertRaises(ValueError):
            matrix.make_config(self.base, {'comms': 'loud'}, self.values)
        with self.assertRaises(ValueError):
            matrix.parse_agent('gemini:pro')

    def test_a_plugin_without_the_situation_setting_skips_only_situation_configurations(self):
        values = {**self.values, 'situation': ['none']}
        build = lambda spec: matrix.make_config(self.base, spec, values)
        configs = matrix.available([{'situation': 'sbar'}, {'comms': 'direct'}], build)
        self.assertEqual([config['comms'] for config in configs], ['direct'])
        with self.assertRaises(ValueError):
            matrix.available([{'comms': 'loud'}], build)
        with self.assertRaises(matrix.Unavailable):
            build({'situation': 'sbar'})
        with self.assertRaises(ValueError):
            matrix.make_config(self.base, {'situation': 'sbra'}, self.values)

    def test_agent_labels(self):
        self.assertEqual(CODEX, {'client': 'codex', 'model': 'gpt-6-luna', 'effort': 'low',
                                 'label': 'codex-gpt-6-luna-low'})
        self.assertEqual(CLAUDE['label'], 'claude-haiku')


class PluginTest(unittest.TestCase):
    def test_seeded_defaults_render_the_configured_policy(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        with tempfile.TemporaryDirectory() as state:
            plugin.seed(PLUGIN, state, matrix.make_config(base, {'style': 'ste', 'threads': 'off'}, values))
            text = plugin.render(PLUGIN, state)
            self.assertIn('## Language standard: ste-inspired', text)
            self.assertIn('Thread tracking is off', text)
            self.assertIsNone(plugin.read_session(state, 'claude'))
        with tempfile.TemporaryDirectory() as state:
            plugin.seed(PLUGIN, state, matrix.make_config(base, 'disabled', values))
            self.assertEqual(plugin.render(PLUGIN, state), '')


class PolicyNotesTest(unittest.TestCase):
    def test_each_hook_part_is_held_to_the_limit_on_its_own(self):
        self.assertEqual(runner.policy_notes([7000, 6000], 'claude', 16000), [])
        [note] = runner.policy_notes([7000, 10500], 'claude', 16000)
        self.assertTrue(note.startswith('hook part 2 is over'))
        self.assertEqual(runner.policy_notes([12000], 'codex', 16000), [])


class PlaceholderTest(unittest.TestCase):
    STATE = {'active': '2', 'threads': {
        '1': {'status': 'closed', 'options': {}},
        '2': {'status': 'open', 'options': {'a': {'status': 'rejected'},
                                            'b': {'status': 'live', 'recommended': True},
                                            'c': {'status': 'live'}}}}}

    def test_active_thread_and_its_recommended_option(self):
        self.assertEqual(runner.fill('{active}{recommended}', 'claude', self.STATE), '2b')
        self.assertEqual(runner.fill('{cmd}set comms direct', 'codex', None), '$dialogue:set comms direct')

    def test_no_threads_falls_back_to_the_first_number_and_letter(self):
        self.assertEqual(runner.fill('{active}{recommended}', 'claude', {'threads': {}}), '1a')


class ParsingTest(unittest.TestCase):
    def test_claude_turn(self):
        events = [
            {'type': 'assistant', 'message': {'content': [
                {'type': 'text', 'text': 'Checking the file.'},
                {'type': 'tool_use', 'id': 't1', 'name': 'Bash',
                 'input': {'command': '/x/bin/dialogue --client claude --session "s" thread open "T" --body b'}}]}},
            {'type': 'user', 'message': {'content': [
                {'type': 'tool_result', 'tool_use_id': 't1', 'content': [{'type': 'text', 'text': 'Opened 1/'}]}]}},
            {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': 'Done.'}]}},
            {'type': 'result', 'subtype': 'success', 'result': 'Done.', 'usage': {'output_tokens': 5},
             'total_cost_usd': 0.01},
        ]
        turn = clients.parse_claude_turn(events)
        self.assertEqual(turn['reply'], 'Done.')
        self.assertEqual(turn['items'][1]['output'], 'Opened 1/')
        self.assertEqual(clients.narration(turn['items']), ['Checking the file.'])
        self.assertEqual(clients.dialogue_op(clients.command_of(turn['items'][1])), 'thread open')

    def test_codex_turn(self):
        events = [
            {'type': 'thread.started', 'thread_id': 'abc'},
            {'type': 'item.completed', 'item': {'type': 'error', 'message': 'hook trust bypassed'}},
            {'type': 'item.completed', 'item': {
                'type': 'command_execution', 'exit_code': 0, 'aggregated_output': 'ok',
                'command': "/bin/zsh -lc '/h/bin/dialogue --client codex set comms direct'"}},
            {'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'Set.'}},
            {'type': 'turn.completed', 'usage': {'input_tokens': 100, 'cached_input_tokens': 60, 'output_tokens': 7}},
        ]
        turn = clients.parse_codex_turn(events)
        self.assertEqual((turn['thread_id'], turn['reply'], turn['notices']), ('abc', 'Set.', ['hook trust bypassed']))
        self.assertEqual(clients.dialogue_op(clients.command_of(turn['items'][0])), 'set')
        self.assertEqual(cost.tokens('codex', turn['usage']),
                         {'input': 40, 'cache_write': 0, 'cache_read': 60, 'output': 7})

    def test_child_sessions_do_not_inherit_the_parent_session(self):
        saved = dict(clients.os.environ)
        try:
            clients.os.environ.update(CLAUDE_EFFORT='xhigh', CLAUDECODE='1', CLAUDE_CODE_OAUTH_TOKEN='kept')
            env = clients.clean_env(DIALOGUE_STATE_DIR='/state')
        finally:
            clients.os.environ.clear()
            clients.os.environ.update(saved)
        self.assertNotIn('CLAUDE_EFFORT', env)
        self.assertNotIn('CLAUDECODE', env)
        self.assertEqual((env['CLAUDE_CODE_OAUTH_TOKEN'], env['DIALOGUE_STATE_DIR']), ('kept', '/state'))

    def test_reading_the_saved_policy_is_detected(self):
        path = '/u/.claude/projects/x/s/tool-results/hook-1-SessionStart-2-1-additionalContext.txt'
        self.assertTrue(clients.reads_policy_file({'type': 'tool', 'name': 'Read', 'input': {'file_path': path}}))
        self.assertFalse(clients.reads_policy_file({'type': 'tool', 'name': 'Read', 'input': {'file_path': '/a.py'}}))
        variant = {'policy_chars': 12000, 'policy_notes': ['over'], 'policy_read': True, 'policy_read_turn': 2}
        self.assertEqual(report.policy_delivery(variant, short=True), 'preview, read t2')
        self.assertEqual(report.policy_delivery({'policy_chars': 9000, 'policy_notes': []}, short=True), 'inline')
        self.assertEqual(report.policy_delivery({'policy_chars': 0, 'policy_notes': []}, short=True), 'none')

    def test_dialogue_op_skips_flags(self):
        self.assertEqual(clients.dialogue_op('/p/bin/dialogue --client claude --session s guideline --default '
                                             'enable bluf'), 'guideline enable')
        self.assertIsNone(clients.dialogue_op('ls -la'))


class MetricsTest(unittest.TestCase):
    TERMS = {'intents': ['FYI', 'WARNING'], 'responses': ['DONE'],
             'frameworks': {'sbar': ['Situation', 'Background', 'Assessment', 'Recommendation']}}

    def test_reply_features(self):
        reply = '\n'.join([
            'WARNING: this deletes data — there is no undo.', "It's gone after that.", '',
            '**Situation:** errors.', '**Background:** a deploy.', '',
            '1. Stop the job.', '2. Check the logs.', '- a bullet', '',
            '| A | B |', '| --- | --- |', '| 1 | 2 |', '',
            '---', '', '### DECISIONS', '', '### 3/ Roll back?', '', '3a/ (recommended) Yes', '3b/ No', '',
            '2 other open threads. Type `=/` to go through them.'])
        values = metrics.reply_metrics(reply, self.TERMS)
        self.assertEqual((values['numbered_items'], values['bullets'], values['tables']), (2, 1, 1))
        self.assertEqual((values['em_dashes'], values['contractions']), (1, 1))
        self.assertTrue(values['decisions_heading'] and values['footer'])
        self.assertEqual((values['thread_headings'], values['option_lines'], values['recommended']), (1, 2, 1))
        self.assertEqual(values['markers'], 'WARNINGx1')
        self.assertEqual(values['framework'], 'sbar 2/4')

    def test_document_rule_features(self):
        reply = '\n'.join([
            'Set the TTL, e.g. 60 seconds. This means the CDN (content delivery network) refetches. `API` is code.',
            '- no lead-in', '  - nested', '',
            'Steps:', '- one', '- two', '',
            'One. Two. Three. Four. Five. Six. Seven.', '',
            '```', 'This is code, i.e. ignored.', '- not a list', '```'])
        values = metrics.reply_metrics(reply, self.TERMS)
        self.assertEqual(values['latin_abbreviations'], 1)
        self.assertEqual(values['unexpanded_acronyms'], 1)
        self.assertEqual(values['bare_demonstratives'], 1)
        self.assertEqual(values['long_paragraphs'], 1)
        self.assertEqual(values['lists_without_lead_in'], 1)
        self.assertEqual(values['nested_items'], 1)


class ComplianceTest(unittest.TestCase):
    NAMES = {'plain_punctuation': 'No em-dashes', 'verdict': 'Verdict first'}

    def values(self, **changes):
        base = {'numbered_items': 0, 'thread_headings': 0, 'decisions_heading': False, 'em_dashes': 0,
                'contractions': 0, 'long_sentences': 0, 'sentences': 2, 'tables': 0, 'framework': '', 'markers': ''}
        return {**base, **changes}

    def test_rules_apply_only_when_the_policy_has_them(self):
        policy = '## Thread protocol\n- No em-dashes: use a comma.\n## Situational framework: sbar\n'
        found = dict(compliance.checks(policy, self.NAMES, 'escalation', 1, '', 'x',
                                       self.values(numbered_items=2, framework='sbar 4/4')))
        self.assertEqual(found, {'threads: no numbered list': False, 'plain_punctuation: no em-dash': True,
                                 'situation sbar: its fields used': True})
        self.assertEqual(compliance.checks('', self.NAMES, 'escalation', 1, '', 'x', self.values()), [])

    def test_numbered_steps_pass_in_a_procedure_only_where_the_protocol_allows_them(self):
        ban = '## Thread protocol\nNever use a numbered list in a reply.\n'
        steps = '## Thread protocol\nNumber a list only for steps that must run in order.\n'
        numbered = self.values(numbered_items=3)
        rules = lambda policy, scenario: [rule for rule, _ in compliance.checks(policy, {}, scenario, 1, '', 'x', numbered)]
        self.assertIn('threads: no numbered list', rules(ban, 'procedure'))
        self.assertNotIn('threads: no numbered list', rules(steps, 'procedure'))
        self.assertIn('threads: no numbered list', rules(steps, 'decisions'))

    def test_verdict_first(self):
        policy = '- Verdict first: say it.'
        [(_, passed)] = compliance.checks(policy, self.NAMES, 'implemented', 1, '', '**Verdict:** No. It raises.',
                                          self.values())
        self.assertTrue(passed)


class JudgeTest(unittest.TestCase):
    def test_parse_takes_the_json_object_and_rejects_others(self):
        self.assertEqual(judge.parse('Here: {"winner": "A", "scores": {}} done')['winner'], 'A')
        self.assertIsNone(judge.parse('{"winner": "C"}'))
        self.assertIsNone(judge.parse('no json'))

    def test_a_pair_keeps_only_the_a_and_b_scores(self):
        class Fake:
            agent = CLAUDE

            def ask(self, system, text):
                return '{"winner": "A", "scores": {"A": {"correct": 5}, "B": {"correct": 3}, "A_note": "x"}}', 0, None

        with tempfile.TemporaryDirectory() as root:
            run_dir = Path(root)
            for name in ('variant', 'base'):
                (run_dir / name).mkdir()
                (run_dir / name / 'turns.json').write_text('[{"sent": "q", "reply": "a"}]', encoding='utf-8')
            pair = {'variant': run_dir / 'variant', 'base': run_dir / 'base', 'agent': 'a', 'scenario': 'implemented',
                    'repeat': 1, 'config': 'ref.-bluf', 'base_slug': 'ref'}
            record = judge.judge_pair(Fake(), pair, matrix.load_json('rubric.json'), run_dir)
        self.assertEqual(record['orders'][0]['scores'], {'variant': {'correct': 5}, 'base': {'correct': 3}})
        self.assertEqual(record['verdict'], 'tie')

    def test_prompt_is_blind_to_settings(self):
        rubric = matrix.load_json('rubric.json')
        turns = [{'sent': 'Is retry on HTTP 503 implemented?', 'reply': 'No.'}]
        text = judge.prompt('implemented', rubric, turns, turns)
        self.assertIn('fetch() raises every HTTPError at once', text)
        self.assertNotIn('pyramid', text)
        self.assertIn('"correct": 1-5', judge.system_prompt(rubric))


class SuitesTest(unittest.TestCase):
    def test_every_suite_plans_against_the_plugin_as_it_is(self):
        base = plugin.fresh_defaults(PLUGIN)
        for name in matrix.load_json('suites.json')['suites']:
            with self.subTest(suite=name):
                self.assertTrue(matrix.cases(PLUGIN, base, [CLAUDE], [name]))


class AblationTest(unittest.TestCase):
    def test_leave_one_out_removes_each_unit_once_and_runs_the_reference_on_every_scenario(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        spec = matrix.load_json('suites.json')['suites']['ablation']['leave_one_out']
        pairs = matrix.leave_one_out(spec, base, values, PLUGIN)
        names = {matrix.slug(config) for _, config in pairs}
        lines = matrix.rule_lines(PLUGIN, 'policy/threads.md')
        self.assertEqual(len(names), 1 + len(values['guidelines']) + len(lines))
        reference = [scenario for scenario, config in pairs if matrix.slug(config) == 'ref']
        self.assertEqual(len(reference), len(set(reference)), reference)
        self.assertIn('decisions', reference)
        unit = next(config for _, config in pairs if matrix.slug(config) == 'ref.-bluf')
        self.assertFalse(unit['guidelines']['bluf'])
        self.assertTrue(unit['guidelines']['tables'])

    def test_sets_remove_their_units_at_once_in_place_of_the_units(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        spec = matrix.load_json('suites.json')['suites']['ablation']['leave_one_out']
        line = 'ref.~threads' + str(matrix.rule_lines(PLUGIN, 'policy/threads.md')[0][0])
        pairs = matrix.leave_one_out(spec, base, values, PLUGIN, sets={'mixed': ['ref.-bluf', line],
                                                                       'one': ['ref.-tables']})
        by_name = {}
        for scenario, config in pairs:
            by_name.setdefault(matrix.slug(config), (config, []))[1].append(scenario)
        self.assertEqual(set(by_name), {'ref', 'ref.*mixed', 'ref.*one'})
        mixed, scenarios = by_name['ref.*mixed']
        self.assertEqual(sorted(scenarios), sorted(by_name['ref'][1]))
        self.assertFalse(mixed['guidelines']['bluf'])
        self.assertTrue(mixed['guidelines']['tables'])
        self.assertEqual(len(mixed['drops']), 1)
        self.assertEqual(mixed['together'], ['ref.-bluf', line])
        self.assertNotIn('decisions', by_name['ref.*one'][1])
        with self.assertRaises(ValueError):
            matrix.leave_one_out(spec, base, values, PLUGIN, sets={'bad': ['ref.-nothing']})

    def test_chosen_units_and_all_of_them_removed_together(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        spec = matrix.load_json('suites.json')['suites']['ablation']['leave_one_out']
        line = 'ref.~threads' + str(matrix.rule_lines(PLUGIN, 'policy/threads.md')[0][0])
        pairs = matrix.leave_one_out(spec, base, values, PLUGIN, units=['ref.-bluf', line], together=True)
        by_name = {}
        for scenario, config in pairs:
            by_name.setdefault(matrix.slug(config), (config, []))[1].append(scenario)
        self.assertEqual(set(by_name), {'ref', 'ref.-bluf', line, 'ref.*together'})
        together, scenarios = by_name['ref.*together']
        self.assertEqual(sorted(scenarios), sorted(by_name['ref'][1]))
        self.assertFalse(together['guidelines']['bluf'])
        self.assertTrue(together['guidelines']['tables'])
        self.assertEqual(together['drops'], by_name[line][0]['drops'])
        self.assertEqual(together['together'], ['ref.-bluf', line])
        with self.assertRaises(ValueError):
            matrix.leave_one_out(spec, base, values, PLUGIN, units=['ref.-nothing'])

    def test_groups_remove_a_guideline_type_or_a_paragraph_at_a_time(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        spec = matrix.load_json('suites.json')['suites']['ablation-groups']['leave_one_out']
        configs = {matrix.slug(config): config for _, config in matrix.leave_one_out(spec, base, values, PLUGIN)}
        language = configs['ref.*type-language']
        self.assertFalse(language['guidelines']['complete_grammar'])
        self.assertTrue(language['guidelines']['bluf'])
        self.assertIn('complete_grammar', language['together'])
        lines = matrix.rule_lines(PLUGIN, 'policy/threads.md')
        blocks = matrix.paragraphs(lines)
        first = configs[f'ref.*threads{blocks[0][0][0]}-{blocks[0][-1][0]}']
        self.assertEqual(len(first['drops']), len(blocks[0]))
        self.assertEqual(sum(len(block) for block in blocks), len(lines))
        types = {entry['type'] for entry in json.loads((PLUGIN / 'policy' / 'guidelines.json').read_text())}
        self.assertEqual(len(configs), 1 + len(types) + len(blocks))

    def test_calibrated_analysis_finds_a_planted_effect_and_not_noise(self):
        rng = random.Random(1)
        rows = {}
        for scenario in ('one', 'two'):
            rows[scenario] = [(config, {'words': rng.gauss(100, 10) + (60 if config == 'ref.-loud' else 0)})
                              for config in ['ref', 'ref.-loud'] + [f'ref.-quiet{n}' for n in range(10)]
                              for _ in range(3)]
        units = sorted({config for config, _ in rows['one'] if config != 'ref'})
        p = ablation.p_values(rows, units, shuffles=200)
        self.assertEqual(ablation.discoveries(p), {'ref.-loud'})

    def test_a_check_that_fails_only_where_its_rule_is_gone_is_an_effect(self):
        rows = [(config, {'rule: check': 0.0 if config == 'ref.-check' else 1.0})
                for config in ['ref', 'ref.-check'] + [f'ref.-quiet{n}' for n in range(8)] for _ in range(4)]
        [(metric, z, moved)] = ablation.scores(rows)['ref.-check']
        self.assertEqual((metric, moved), ('rule: check', -1.0))
        self.assertLess(z, -10)
        p = ablation.p_values({'one': rows}, sorted({config for config, _ in rows} - {'ref'}), shuffles=200)
        self.assertEqual(ablation.discoveries(p), {'ref.-check'})

    def test_a_session_without_a_metric_is_left_out_of_it(self):
        rng = random.Random(2)
        rows = [(config, {'words': rng.gauss(100, 10),
                          **({} if config == 'ref.-check' else {'rule: check': float(rng.random() < 0.8)})})
                for config in ['ref', 'ref.-check'] + [f'ref.-quiet{n}' for n in range(5)] for _ in range(3)]
        tests = ablation.scores(rows)
        self.assertEqual([metric for metric, _, _ in tests['ref.-check']], ['words'])
        self.assertIn('rule: check', [metric for metric, _, _ in tests['ref.-quiet0']])
        self.assertEqual(ablation.discoveries(ablation.p_values({'one': rows}, ['ref.-check'], shuffles=100)), set())

    def test_drop_lines_removes_only_the_named_lines(self):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / 'policy' / 'threads.md'
            target.parent.mkdir()
            target.write_text('one\ntwo\nthree\n', encoding='utf-8')
            runner.drop_lines(root, ['policy/threads.md:2'])
            self.assertEqual(target.read_text(encoding='utf-8'), 'one\nthree\n')


class CostTest(unittest.TestCase):
    def test_price_and_estimate(self):
        prices = cost.pricing()
        rates = cost.rates(prices, CLAUDE)
        self.assertEqual(rates, prices['claude']['models']['claude-haiku-5-5'])
        self.assertAlmostEqual(cost.price(rates, {'input': 1_000_000, 'cache_write': 0, 'cache_read': 0,
                                                  'output': 1_000_000}), 0.6)
        self.assertIsNone(cost.rates(prices, matrix.parse_agent('codex:unknown-model')))
        case = {'agent': CLAUDE, 'scenario': {'turns': ['a', 'b']}}
        [row] = cost.estimate([case, case], prices)
        self.assertEqual((row['sessions'], row['turns'], row['profile']), (2, 4, 'default'))

    def test_claude_turn_cost_is_the_increase_of_the_running_total(self):
        run = runner.Run.__new__(runner.Run)
        run.prices = cost.pricing()
        turns = [{'cost_usd': 0.004, 'usage': {}}, {'cost_usd': 0.007, 'usage': {}}]
        run.account('claude', CLAUDE, turns)
        self.assertEqual([turn['cost_usd'] for turn in turns], [0.004, 0.003])


if __name__ == '__main__':
    unittest.main()

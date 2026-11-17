"""The testbed's deterministic parts: the matrix, placeholders, parsing, metrics, cost and rendering."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import clients  # noqa: E402
import cost  # noqa: E402
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
        cases = matrix.cases(PLUGIN, self.base, [CLAUDE, CODEX], ['situation'], config_match=['sbar'], limit=2)
        self.assertEqual([case['agent']['client'] for case in cases], ['claude', 'claude', 'codex', 'codex'])
        self.assertTrue(all('sbar' in case['key'] for case in cases))

    def test_unknown_values_are_rejected(self):
        with self.assertRaises(ValueError):
            matrix.make_config(self.base, {'comms': 'loud'}, self.values)
        with self.assertRaises(ValueError):
            matrix.parse_agent('gemini:pro')

    def test_agent_labels(self):
        self.assertEqual(CODEX, {'client': 'codex', 'model': 'gpt-6-luna', 'effort': 'low',
                                 'label': 'codex-gpt-6-luna-low'})
        self.assertEqual(CLAUDE['label'], 'claude-haiku')


class PluginTest(unittest.TestCase):
    def test_seeded_defaults_render_the_configured_policy(self):
        values = matrix.catalog(PLUGIN)
        base = plugin.fresh_defaults(PLUGIN)
        with tempfile.TemporaryDirectory() as state:
            plugin.seed(PLUGIN, state, matrix.make_config(base, {'situation': 'sbar', 'threads': 'off'}, values))
            text = plugin.render(PLUGIN, state)
            self.assertIn('## Situational framework: sbar', text)
            self.assertIn('Thread tracking is off', text)
            self.assertIsNone(plugin.read_session(state, 'claude'))
        with tempfile.TemporaryDirectory() as state:
            plugin.seed(PLUGIN, state, matrix.make_config(base, 'disabled', values))
            self.assertEqual(plugin.render(PLUGIN, state), '')


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

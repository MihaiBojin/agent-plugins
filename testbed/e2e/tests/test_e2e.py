import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import e2e  # noqa: E402
import pushed_tags  # noqa: E402

REPOSITORY = Path(__file__).resolve().parents[3]


class FrontMatter(unittest.TestCase):
    def test_reads_quoted_patterns_lists_and_bare_values(self):
        fields, body = e2e.front_matter(
            "---\ntype: regex\npattern: 'it''s \\bhere\\b'\ntags: [e2e, slow]\nmax_turns: 10\n---\n\nThe body.\n")
        self.assertEqual(fields, {'type': 'regex', 'pattern': "it's \\bhere\\b", 'tags': ['e2e', 'slow'],
                                  'max_turns': '10'})
        self.assertEqual(body, 'The body.')

    def test_a_file_without_front_matter_is_all_body(self):
        self.assertEqual(e2e.front_matter('Only text.'), ({}, 'Only text.'))


class RegexGrader(unittest.TestCase):
    def test_passes_when_the_pattern_is_found(self):
        self.assertTrue(e2e.regex_passes({'pattern': r'WARNING[\s\S]*rm -rf'}, 'WARNING: data loss.\n\nrm -rf x'))
        self.assertFalse(e2e.regex_passes({'pattern': r'WARNING[\s\S]*rm -rf'}, 'rm -rf x\n\nWARNING: too late'))

    def test_not_contains_passes_when_the_pattern_is_absent(self):
        grader = {'pattern': r'\bpreviously\b', 'flags': 'i', 'match': 'not_contains'}
        self.assertTrue(e2e.regex_passes(grader, 'The sender has a budget.'))
        self.assertFalse(e2e.regex_passes(grader, 'Previously it retried.'))

    def test_count_needs_the_exact_number(self):
        grader = {'pattern': r'^\d+\. ', 'match': 'count:1'}
        self.assertTrue(e2e.regex_passes(grader, '1. Run it.'))
        self.assertFalse(e2e.regex_passes({**grader, 'match': 'count:2'}, '1. Run it.'))

    def test_a_start_anchor_holds_only_at_the_start_of_the_reply(self):
        grader = {'pattern': r'^\s*Title: \S[^\n]*\n+(?!#)\S'}
        self.assertTrue(e2e.regex_passes(grader, 'Title: Add a timeout\n\nThe client stops after 30 s.'))
        self.assertFalse(e2e.regex_passes(grader, 'Title: Add a timeout\n\n## Why\n\nIt hung.'))
        self.assertFalse(e2e.regex_passes(grader, 'Here it is.\n\nTitle: Add a timeout\n\nThe client stops.'))


class Cases(unittest.TestCase):
    def test_loads_only_the_cases_tagged_e2e_with_their_regex_graders(self):
        with tempfile.TemporaryDirectory() as scratch:
            evals = Path(scratch) / 'evals'
            for name, tags in (('e2e-writer', '[e2e]'), ('postmortem', '[slow]')):
                (evals / name / 'graders').mkdir(parents=True)
                (evals / name / 'prompt.md').write_text(f'---\ntags: {tags}\n---\n\nWrite it.\n')
                (evals / name / 'graders' / 'shape.md').write_text("---\ntype: regex\npattern: '^# '\n---\n")
                (evals / name / 'graders' / 'judged.md').write_text('---\ntype: llm\n---\n\nPass if good.\n')
            cases = e2e.load_cases(scratch)
        self.assertEqual([case['name'] for case in cases], ['e2e-writer'])
        self.assertEqual(cases[0]['skill'], 'writer')
        self.assertEqual(cases[0]['prompt'], 'Write it.')
        self.assertEqual([grader['name'] for grader in cases[0]['graders']], ['shape'])

    def test_every_e2e_case_in_this_repository_names_a_skill_of_its_plugin(self):
        for plugin in sorted((REPOSITORY / 'plugins').iterdir()):
            for case in e2e.load_cases(plugin):
                with self.subTest(case=case['name']):
                    self.assertTrue((plugin / 'skills' / case['skill'] / 'SKILL.md').is_file())
                    self.assertTrue(case['graders'])


class Codex(unittest.TestCase):
    EVENTS = [
        {'type': 'thread.started', 'thread_id': 't1'},
        {'type': 'item.completed', 'item': {'type': 'command_execution', 'exit_code': 0,
                                            'command': "/bin/zsh -lc 'cat /home/plugins/x/skills/writer/SKILL.md'"}},
        {'type': 'item.completed', 'item': {'type': 'agent_message', 'text': 'Reading the skill.'}},
        {'type': 'item.completed', 'item': {'type': 'agent_message', 'text': '# The document'}},
        {'type': 'turn.completed', 'usage': {'input_tokens': 900, 'cached_input_tokens': 500, 'output_tokens': 40}},
    ]

    def test_the_reply_is_the_last_message_and_the_usage_is_kept(self):
        turn = e2e.parse_codex([json.dumps(event) for event in self.EVENTS] + ['not json'])
        self.assertEqual(turn['reply'], '# The document')
        self.assertEqual(turn['usage']['output_tokens'], 40)
        self.assertIsNone(turn['error'])

    def test_a_skill_counts_as_loaded_when_a_command_read_its_file(self):
        turn = e2e.parse_codex([json.dumps(event) for event in self.EVENTS])
        self.assertTrue(e2e.skill_was_read(turn['commands'], 'writer'))
        self.assertFalse(e2e.skill_was_read(turn['commands'], 'other'))

    def test_a_case_with_a_project_runs_read_only_in_its_own_copy(self):
        plugin = REPOSITORY / 'plugins' / 'technical-writer'
        case = next(case for case in e2e.load_cases(plugin) if case['skill'] == 'audit-project-readme')
        with tempfile.TemporaryDirectory() as scratch:
            def read_project(command, *, cwd, **options):
                self.assertEqual(command[command.index('--sandbox') + 1], 'read-only')
                self.assertTrue(cwd.is_relative_to(Path(scratch)))
                self.assertIn('--input', (cwd / 'README.md').read_text())
                self.assertIn('--manifest', (cwd / 'pin-count.sh').read_text())
                self.assertFalse((cwd / 'graders').exists())
                return subprocess.CompletedProcess(command, 0, '', '')

            with patch.object(e2e, 'run', side_effect=read_project):
                e2e.run_codex_case(case, Mock(), 'test-model', Path(scratch))
            results = Path(scratch) / 'codex' / case['name']
            self.assertTrue((results / 'reply.md').exists())
            self.assertFalse((results / 'README.md').exists())

    def test_trace_grader_requires_observed_fixture_output(self):
        plugin = REPOSITORY / 'plugins' / 'technical-writer'
        case = next(case for case in e2e.load_cases(plugin) if case['skill'] == 'write-project-readme')
        with tempfile.TemporaryDirectory() as scratch:
            def grades(output, exit_code):
                item = {'type': 'command_execution', 'command': 'sh level-count.sh --level WARN examples/events.txt',
                        'aggregated_output': output, 'exit_code': exit_code}
                event = {'type': 'item.completed', 'item': item}
                result = subprocess.CompletedProcess([], 0, json.dumps(event), '')
                with tempfile.TemporaryDirectory(dir=scratch) as out, patch.object(e2e, 'run', return_value=result):
                    rows, _ = e2e.run_codex_case(case, Mock(), 'test-model', Path(out))
                return {name: passed for _, _, name, passed in rows}

            self.assertTrue(grades('WARN=2\n', 0)['run_example'])
            self.assertTrue(grades('Usage text\nWARN=2\nmore output\n', 0)['run_example'])
            self.assertFalse(grades('Operation not permitted', 2)['run_example'])
            self.assertFalse(grades('WARN=2\n', 1)['run_example'])

    def test_claude_trace_grader_needs_successful_tool_output(self):
        plugin = REPOSITORY / 'plugins' / 'technical-writer'
        case = next(case for case in e2e.load_cases(plugin) if case['skill'] == 'audit-project-readme')
        grader = next(grader for grader in case['graders'] if grader['name'] == 'check_cli')
        for kind, failed, expected in [('tool_result', False, True), ('tool_result', True, False),
                                       ('text', False, False)]:
            event = {'type': kind, 'content': 'observed output\n2\n', 'is_error': failed}
            with self.subTest(kind=kind, failed=failed):
                self.assertEqual(e2e.regex_passes(grader, json.dumps(event)), expected)

    def test_a_failed_turn_reports_its_message(self):
        turn = e2e.parse_codex([json.dumps({'type': 'turn.failed', 'error': {'message': 'no quota'}})])
        self.assertEqual(turn['error'], 'no quota')


class ClaudeTrace(unittest.TestCase):
    def test_scaffold_requires_the_two_copy_only_fixtures(self):
        plugin = REPOSITORY / 'plugins' / 'technical-writer'
        with tempfile.TemporaryDirectory() as scratch:
            copy = Path(scratch) / plugin.name
            shutil.copytree(plugin, copy)
            self.assertTrue(e2e.claude_fixture_tools(copy))
            unexpected = copy / 'evals' / 'another-case' / 'case.yaml'
            unexpected.parent.mkdir()
            unexpected.write_text('context: {scaffold_script: setup.sh}\n')
            self.assertEqual(e2e.claude_fixture_tools(copy), [])
            unexpected.unlink()
            approved = copy / 'evals' / 'e2e-audit-project-readme'
            script = approved / 'scaffold.sh'
            original = script.read_bytes()
            script.write_text('echo unexpected\n')
            self.assertEqual(e2e.claude_fixture_tools(copy), [])
            script.write_bytes(original)
            (approved / 'case.yaml').write_text('context: {scaffold_script: setup.sh}\n')
            self.assertEqual(e2e.claude_fixture_tools(copy), [])

    def test_the_reply_is_the_result_of_the_last_result_event(self):
        lines = [json.dumps({'type': 'assistant', 'message': {}}), 'not json',
                 json.dumps({'type': 'result', 'result': 'Title: Add a timeout'})]
        self.assertEqual(e2e.claude_reply(lines), 'Title: Add a timeout')

    def test_keeps_the_trace_and_the_reply_and_deletes_the_scaffold(self):
        with tempfile.TemporaryDirectory() as scratch:
            scaffold = Path(scratch) / 'e-abc'
            (scaffold / 'out').mkdir(parents=True)
            trace = scaffold / 'out' / 'trace.jsonl'
            trace.write_text(json.dumps({'type': 'result', 'result': 'the reply'}) + '\n', encoding='utf-8')
            (scaffold / 'sealed' / 'inner').mkdir(parents=True)
            (scaffold / 'sealed').chmod(0)  # as the eval leaves it
            scaffold.chmod(0o500)
            kept = Path(scratch) / 'claude' / 'case'
            e2e.keep_claude_trace(str(trace), kept)
            self.assertEqual((kept / 'reply.md').read_text(encoding='utf-8'), 'the reply')
            self.assertTrue((kept / 'events.jsonl').is_file())
            self.assertFalse(scaffold.exists())

    def test_a_run_without_a_trace_keeps_nothing(self):
        with tempfile.TemporaryDirectory() as scratch:
            e2e.keep_claude_trace(None, Path(scratch) / 'case')
            self.assertFalse((Path(scratch) / 'case').exists())


class PushedTags(unittest.TestCase):
    def test_finds_release_tags_and_skips_branches_other_tags_and_deletions(self):
        lines = [
            'refs/heads/main 1111111 refs/heads/main 2222222',
            'refs/tags/technical-writer/v0.2.0 aaaaaaa refs/tags/technical-writer/v0.2.0 0000000',
            'refs/tags/v1.0.0 bbbbbbb refs/tags/v1.0.0 0000000',
            '(delete) 0000000 refs/tags/readme/v0.1.0 ccccccc',
            'refs/tags/readme/v0.1.1 0000000 refs/tags/readme/v0.1.1 ccccccc',
        ]
        self.assertEqual(pushed_tags.released(lines), [('technical-writer', 'aaaaaaa')])

    def test_exports_the_plugin_as_the_commit_has_it(self):
        with tempfile.TemporaryDirectory() as scratch:
            repository, destination = Path(scratch) / 'repo', Path(scratch) / 'out'
            (repository / 'plugins' / 'writer').mkdir(parents=True)
            destination.mkdir()
            (repository / 'plugins' / 'writer' / 'README.md').write_text('tagged\n')
            git = ['git', '-C', str(repository), '-c', 'commit.gpgsign=false', '-c', 'user.name=t',
                   '-c', 'user.email=t@example.invalid']
            for arguments in (['init', '-q'], ['add', '-A'], ['commit', '-q', '-m', 'one']):
                subprocess.run([*git, *arguments], check=True, capture_output=True)
            (repository / 'plugins' / 'writer' / 'README.md').write_text('edited after the tag\n')
            exported = pushed_tags.export(repository, 'HEAD', 'writer', destination)
            self.assertEqual((exported / 'README.md').read_text(), 'tagged\n')
            self.assertIsNone(pushed_tags.export(repository, 'HEAD', 'missing', destination))


if __name__ == '__main__':
    unittest.main()

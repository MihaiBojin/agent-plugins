import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'lib' / 'cli.py'


class DialogueTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = dict(os.environ, DIALOGUE_STATE_DIR=self.tmp.name, PYTHONDONTWRITEBYTECODE='1')

    def run_cli(self, *args, session='a', client='codex', payload=None, ok=True):
        cmd = [sys.executable, str(CLI), '--client', client, '--session', session, *args]
        result = subprocess.run(cmd, env=self.env, input=json.dumps(payload) if payload else None,
                                capture_output=True, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def state(self, **kwargs):
        return json.loads(self.run_cli('state', **kwargs).stdout)

    def hook_context(self, payload, client='codex'):
        """What both SessionStart hook parts inject, joined, or '' when neither prints."""
        parts = []
        for args in (('hook',), ('hook', '--part', 'threads')):
            output = self.run_cli(*args, client=client, payload=payload).stdout
            if output:
                parts.append(json.loads(output)['hookSpecificOutput']['additionalContext'])
        return '\n\n'.join(parts)

    def test_settings_are_read_only_and_do_not_activate(self):
        self.assertIn('| enabled |', self.run_cli('settings').stdout)
        self.assertFalse(self.state()['settings']['enabled'])
        self.assertEqual(list(Path(self.tmp.name).iterdir()), [])

    @unittest.skipIf(os.name == 'nt' or (hasattr(os, 'geteuid') and os.geteuid() == 0),
                     'requires POSIX file permissions for a non-root user')
    def test_denied_state_writes_explain_codex_permission_and_preserve_records(self):
        root = Path(self.tmp.name) / 'dialogue state'
        self.env['DIALOGUE_STATE_DIR'] = str(root)
        self.env['CODEX_HOME'] = str(Path(self.tmp.name) / 'codex home')
        self.run_cli('enable')
        saved = (root / 'sessions' / 'codex' / 'a.json').read_bytes()
        lock = root / '.lock'
        lock.chmod(0o400)
        self.addCleanup(lock.chmod, 0o600)
        for args, payload in ((('thread', 'open', 'Denied'), None),
                              (('defaults', 'set', 'enabled', 'on'), None),
                              (('hook',), {'session_id': 'a', 'source': 'resume'})):
            with self.subTest(args=args):
                result = self.run_cli(*args, payload=payload, ok=False)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')
                self.assertIn(str(lock), result.stderr)
                self.assertIn('sandbox_workspace_write.writable_roots', result.stderr)
                self.assertIn(str(root), result.stderr)
                self.assertIn(str(Path(self.env['CODEX_HOME']) / 'config.toml'), result.stderr)
                self.assertIn('restart', result.stderr.lower())
                self.assertEqual((root / 'sessions' / 'codex' / 'a.json').read_bytes(), saved)
                self.assertFalse((root / 'defaults.json').exists())
        result = self.run_cli('enable', client='claude', ok=False)
        self.assertIn(str(lock), result.stderr)
        self.assertNotIn('sandbox_workspace_write', result.stderr)

    def test_sessions_keep_defaults_snapshot_and_explicit_off(self):
        self.run_cli('enable')
        self.run_cli('set', 'focus', 'off')
        self.run_cli('defaults', 'set', 'enabled', 'on')
        self.assertFalse(self.state()['settings']['focus'])
        self.assertTrue(self.state(session='b')['settings']['focus'])
        self.run_cli('disable')
        result = self.run_cli('hook', payload={'session_id': 'a', 'source': 'resume'})
        self.assertEqual(result.stdout, '')
        self.assertTrue(self.state(session='b')['settings']['enabled'])

    def test_hook_restores_each_client_and_compaction(self):
        for client in ('codex', 'claude'):
            self.run_cli('enable', client=client)
            self.run_cli('thread', 'open', 'Choose storage', '--body', 'Need a portable runtime', client=client)
            for source in ('startup', 'resume', 'compact'):
                context = self.hook_context({'session_id': 'a', 'source': source}, client=client)
                self.assertIn('Choose storage', context)
                self.assertIn('Need a portable runtime', context)
        self.run_cli('disable', client='codex')
        self.assertTrue(self.state(client='claude')['settings']['enabled'])

    def test_a_resumed_session_sees_the_last_settled_decisions(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'Duplicates')
        self.run_cli('thread', 'open', 'Blank rows')
        self.run_cli('thread', 'option', '1', 'Keep the first', '--recommended')
        self.run_cli('thread', 'choose', '1', 'a')
        self.assertIn('Outcome: chose 1a/ Keep the first', self.run_cli('thread', 'show', '1').stdout)
        self.assertNotIn('Outcome', self.run_cli('thread', 'show', '2').stdout)
        context = self.hook_context({'session_id': 'a', 'source': 'resume'})
        self.assertIn('- 1/ Duplicates: chose 1a/ Keep the first', context)
        for number in range(3, 14):
            self.run_cli('thread', 'open', f'Topic {number}')
            self.run_cli('thread', 'close', str(number))
        context = self.hook_context({'session_id': 'a', 'source': 'compact'})
        self.assertIn('- 13/ Topic 13: no option chosen', context)
        self.assertIn('- 4/ Topic 4', context)
        self.assertNotIn('- 3/ Topic 3', context)
        self.assertNotIn('- 1/ Duplicates', context)

    def test_installed_hook_is_silent_until_enabled(self):
        self.assertEqual(self.hook_context({'session_id': 'fresh', 'source': 'startup'}), '')
        self.run_cli('defaults', 'set', 'enabled', 'on')
        self.assertEqual(self.hook_context({'session_id': 'fresh', 'source': 'resume'}), '')

    def test_each_hook_part_fits_the_inline_limit_and_risk_levels_print_once(self):
        # Claude Code puts a hook's context into the conversation only up to 10,000 characters.
        self.run_cli('enable')
        for key, value in (('comms', 'pyramid'), ('style', 'ste'), ('signals', 'full')):
            self.run_cli('set', key, value)
        for args in (('hook',), ('hook', '--part', 'threads')):
            output = self.run_cli(*args, payload={'session_id': 'a', 'source': 'startup'}).stdout
            context = json.loads(output)['hookSpecificOutput']['additionalContext']
            self.assertLessEqual(len(context), 10_000)
        rendered = self.run_cli('render').stdout
        self.assertEqual(rendered.count('Irreversible harm is possible'), 1)
        self.assertNotIn('Effective settings', rendered)

    def test_thread_ids_and_options_are_never_reused(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'One')
        self.run_cli('thread', 'option', '1', 'Python')
        self.run_cli('thread', 'option', '1', 'Bash')
        self.run_cli('thread', 'reject', '1', 'a')
        self.run_cli('thread', 'option', '1', 'Node')
        result = self.run_cli('thread', 'show', '1').stdout
        self.assertNotIn('1a/', result)
        self.assertIn('1c/', result)
        self.run_cli('thread', 'choose', '1', 'b')
        self.assertEqual(self.state()['threads']['1']['status'], 'closed')
        self.run_cli('thread', 'reopen', '1')
        self.assertNotIn('1b/', self.run_cli('thread', 'show', '1').stdout)
        self.run_cli('thread', 'open', 'Two')
        self.assertIn('2', self.state()['threads'])
        self.run_cli('thread', 'open', 'Child', '--parent', '1', ok=False)

    def test_recommended_option_comes_first_and_is_marked(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'Refuse nested names', '--body', 'Both commands fail the same way.')
        self.run_cli('thread', 'option', '1', 'Refuse in all three commands', '--recommended')
        result = self.run_cli('thread', 'option', '1', "Leave git's error").stdout
        self.assertIn('1a/ (recommended) Refuse in all three commands\n1b/ Leave git\'s error\n\nBoth commands', result)
        self.run_cli('thread', 'option', '1', 'Late pick', '--recommended', ok=False)
        self.assertNotIn('Late pick', self.run_cli('thread', 'show', '1').stdout)

    def test_related_thread_lists_after_the_thread_it_relates_to(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'abc')
        self.run_cli('thread', 'open', 'def')
        shown = self.run_cli('thread', 'open', 'xyz', '--related', '1').stdout
        self.assertIn('### 3/ xyz\n\nRelated: 1/', shown)
        listed = self.run_cli('thread', 'list').stdout
        self.assertLess(listed.index('### 1/'), listed.index('### 3/'))
        self.assertLess(listed.index('### 3/'), listed.index('### 2/'))
        self.run_cli('thread', 'close', '1')
        self.assertEqual(self.state()['threads']['3']['status'], 'open')
        self.run_cli('thread', 'open', 'nothing', '--related', '9', ok=False)

    def test_focus_compact_and_audit_preserve_hidden_threads(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'First')
        self.run_cli('thread', 'open', 'Second')
        rendered = self.run_cli('render').stdout
        self.assertIn('First', rendered)
        self.assertNotIn('### 2/ Second', rendered)
        self.assertIn('1 other open thread. Type `=/` to go through them one at a time or `=//` to see them all.', rendered)
        self.assertIn('`=/` goes through the open threads one at a time', rendered)
        self.assertNotIn('headings only', rendered)
        self.assertIn('`### DECISIONS`', rendered)
        self.assertIn('Second', self.run_cli('thread', 'list').stdout)
        self.run_cli('set', 'compact', 'off')
        self.assertIn('Second', self.run_cli('render').stdout)
        self.run_cli('thread', 'close', '1')
        self.assertEqual(self.state()['active'], '2')

    def test_concurrent_allocations_are_not_lost(self):
        self.run_cli('enable')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda n: self.run_cli('thread', 'open', f'Issue {n}'), range(12)))
        self.assertEqual(set(self.state()['threads']), {str(n) for n in range(1, 13)})

    def test_packaged_hooks_execute_with_each_client_payload(self):
        for client, filename in (('claude', 'hooks.json'), ('codex', 'codex.json')):
            config = json.loads((ROOT / 'hooks' / filename).read_text())
            commands = [hook['command'] for hook in config['hooks']['SessionStart'][0]['hooks']]
            self.assertEqual(len(commands), 2)
            env = dict(self.env, CLAUDE_PLUGIN_ROOT=str(ROOT), PLUGIN_ROOT=str(ROOT))
            payload = json.dumps({'session_id': 'packaged', 'source': 'startup'})
            for command in commands:
                result = subprocess.run(['bash', '-c', command], env=env, input=payload,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')
            self.run_cli('enable', session='packaged', client=client)
            contexts = []
            for command in commands:
                result = subprocess.run(['bash', '-c', command], env=env, input=payload,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                contexts.append(json.loads(result.stdout)['hookSpecificOutput']['additionalContext'])
            self.assertIn(client + ' session packaged', contexts[0])
            self.assertIn('## Thread protocol', contexts[1])
            self.assertNotIn('## Thread protocol', contexts[0])

    def test_rejected_transition_preserves_saved_bytes(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'One')
        self.run_cli('thread', 'option', '1', 'Python')
        self.run_cli('thread', 'reject', '1', 'a')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        saved = path.read_bytes()
        self.run_cli('thread', 'choose', '1', 'a', ok=False)
        self.assertEqual(path.read_bytes(), saved)

    def test_threads_and_style_can_be_disabled_independently(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'Kept')
        out = self.run_cli('set', 'threads', 'off').stdout
        self.assertNotIn('### 1/ Kept', out)
        self.assertIn('## Communication profile: pyramid', out)
        self.run_cli('thread', 'open', 'No', ok=False)
        self.run_cli('set', 'threads', 'on')
        out = self.run_cli('set', 'comms', 'plain').stdout
        self.assertIn('### 1/ Kept', out)
        self.assertNotIn('## Communication profile: pyramid', out)

    def test_communication_profiles_and_guidelines(self):
        self.assertIn('no guidelines are active', self.run_cli('guidelines').stdout)
        self.run_cli('enable')
        self.assertIn('pyramid', self.run_cli('profiles').stdout)
        self.assertIn('BLUF', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'direct')
        self.assertEqual(self.state()['settings']['communication_profile'], 'direct')
        enabled = self.run_cli('guidelines').stdout
        self.assertIn('(8/19 enabled)', enabled)
        self.assertIn('No routine narration', enabled)
        self.assertIn('## Communication profile: direct', self.run_cli('render').stdout)
        self.run_cli('set', 'communication_profile', 'efficient')
        self.assertIn('(7/19 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'plain')
        self.assertIn('(0/19 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'invalid', ok=False)

    def test_pyramid_renders_the_rules_it_selects(self):
        self.run_cli('enable')
        rendered = self.run_cli('render').stdout
        for text in ('- Verdict first: For implementation questions',
                     '- One recommendation:', '- Tables for comparisons:', '- No preamble or recap:',
                     '- Plain punctuation: No em-dashes', '- Clear pronouns:'):
            self.assertIn(text, rendered)
        self.assertNotIn('Short routine replies', rendered)
        profiles = json.loads((ROOT / 'policy' / 'profiles.json').read_text())
        self.assertFalse(any('instruction' in profile for profile in profiles.values()))
        self.run_cli('set', 'comms', 'efficient')
        self.assertIn('- Short routine replies: Routine replies take one to three sentences.',
                      self.run_cli('render').stdout)

    def test_risk_levels_come_from_one_definition(self):
        self.run_cli('enable')
        self.assertNotIn('Risk levels:', self.run_cli('render').stdout)
        signals = json.loads((ROOT / 'policy' / 'signals.json').read_text())
        meanings = {item['id']: item['meaning'] for item in signals['intents']}
        self.assertNotIn('RISK', meanings)
        levels = '\n'.join(['Risk levels:', f"- WARNING: {meanings['WARNING']}", f"- CAUTION: {meanings['CAUTION']}"])
        self.run_cli('set', 'style', 'ste')
        self.assertIn(levels, self.run_cli('render').stdout)
        self.run_cli('set', 'style', 'plain')
        self.run_cli('set', 'signals', 'intent')
        rendered = self.run_cli('render').stdout
        self.assertIn(f"- CAUTION: {meanings['CAUTION']}", rendered)
        self.assertNotIn('- RISK:', rendered)

    def test_consistent_guideline_commands(self):
        self.assertIn('Guideline groups (Dialogue disabled)', self.run_cli('guidelines', 'group', 'list').stdout)
        self.assertIn('bluf [off, inactive]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('enable')
        all_rules = self.run_cli('guidelines', 'list').stdout
        self.assertIn('bluf [on, profile]', all_rules)
        self.assertIn('warnings [off, profile]', all_rules)
        groups = self.run_cli('guidelines', 'group', 'list').stdout
        self.assertIn('brevity: 3/6 enabled', groups)
        self.assertNotIn('\\n', groups)
        self.assertEqual(len(groups.splitlines()), 6)
        assert_group = self.run_cli('guidelines', 'group', 'list', 'risk').stdout
        self.assertIn('warnings', assert_group)
        self.assertNotIn('bluf', assert_group)
        self.run_cli('guideline', 'group', 'enable', 'risk')
        self.assertIn('warnings [on, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'disable', 'plain_words')
        self.assertIn('plain_words [off, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'enable', 'plain_words')
        self.assertIn('plain_words [on, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'reset', 'plain_words')
        self.assertIn('plain_words [off, profile]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'disable', 'risk')
        self.assertIn('warnings [off, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'reset', 'risk')
        self.assertIn('warnings [off, profile]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'enable', 'invalid', ok=False)
        self.run_cli('guidelines', 'group', 'list', 'invalid', ok=False)
        self.run_cli('guideline', 'group', 'enable', ok=False)

    def test_guideline_legacy_forms_still_work(self):
        self.run_cli('enable')
        self.run_cli('guideline', 'on', 'plain_words')
        self.assertIn('plain_words [on, override]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'group', 'brevity', 'off')
        self.assertIn('sufficient [off, override]', self.run_cli('guidelines', '--all', '--group', 'brevity').stdout)
        self.run_cli('guideline', 'group', 'brevity', 'reset')
        self.assertIn('sufficient [on, profile]', self.run_cli('guidelines', 'list').stdout)

    def test_guideline_individual_and_group_overrides(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'plain')
        self.assertIn('(0/19 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'on', 'bluf')
        self.assertIn('BLUF', self.run_cli('render').stdout)
        self.assertIn('(1/19 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'off', 'bluf')
        self.assertIn('(0/19 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'reset', 'bluf')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.run_cli('guideline', 'group', 'risk', 'on')
        enabled = self.run_cli('guidelines', '--group', 'risk').stdout
        self.assertIn('warnings', enabled)
        self.assertNotIn('bluf', enabled)
        self.assertEqual(len(self.state()['settings']['guideline_overrides']), 3)
        self.run_cli('guideline', 'group', 'risk', 'reset')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.assertIn('warnings [off, profile]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'group', 'invalid', 'on', ok=False)
        self.run_cli('guideline', 'on', 'missing', ok=False)
        self.run_cli('guideline', 'on', 'bluf', 'off', ok=False)

    def test_guideline_overrides_persist_across_sessions_and_upgrade(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'plain')
        self.run_cli('guideline', 'on', 'plain_words')
        self.assertIn('Familiar technical words', self.run_cli('render').stdout)
        for source in ('resume', 'compact'):
            result = self.run_cli('hook', payload={'session_id': 'a', 'source': source})
            rendered = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
            self.assertIn('Familiar technical words', rendered)
        self.run_cli('set', 'comms', 'efficient')
        self.assertTrue(self.state()['settings']['guideline_overrides']['plain_words'])
        self.run_cli('guideline', 'reset', 'all')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.assertNotIn('Familiar technical words', self.run_cli('render').stdout)
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        del data['settings']['guideline_overrides']
        path.write_text(json.dumps(data))
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})

    def test_ste_style_rules_can_be_overridden(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'plain')
        self.run_cli('set', 'style', 'ste')
        self.assertIn('(6/19 enabled)', self.run_cli('guidelines').stdout)
        self.assertIn('plain_words [on, style]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'off', 'plain_words')
        enabled = self.run_cli('guidelines', '--all').stdout
        self.assertIn('plain_words [off, override]', enabled)
        self.assertNotIn('Familiar technical words', self.run_cli('render').stdout)
        self.run_cli('guideline', 'reset', 'plain_words')
        self.assertIn('plain_words [on, style]', self.run_cli('guidelines', '--all').stdout)

    def test_default_guideline_overrides_apply_only_to_new_sessions(self):
        self.run_cli('enable')
        self.run_cli('guideline', '--default', 'on', 'warnings')
        self.run_cli('guideline', '--default', 'group', 'brevity', 'off')
        current = self.state()['settings']
        self.assertEqual(current['guideline_overrides'], {})
        future = self.state(session='future')['settings']['guideline_overrides']
        self.assertTrue(future['warnings'])
        self.assertFalse(future['sufficient'])
        self.run_cli('guideline', '--default', 'reset', 'warnings')
        later = self.state(session='later')['settings']['guideline_overrides']
        self.assertNotIn('warnings', later)
        self.assertIn('warnings', future)
        self.assertNotIn('warnings', current['guideline_overrides'])

    def test_bad_guideline_overrides_do_not_change_corrupt_state(self):
        self.run_cli('enable')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        original = json.loads(path.read_text())
        for override in ({'typo': True}, {'bluf': 'yes'}, ['bluf']):
            data = json.loads(json.dumps(original))
            data['settings']['guideline_overrides'] = override
            path.write_text(json.dumps(data))
            saved = path.read_bytes()
            self.run_cli('guidelines', '--all', ok=False)
            self.assertEqual(path.read_bytes(), saved)
        path.write_text(json.dumps(original))

    def test_saved_custom_profile_loads_as_plain(self):
        self.run_cli('enable')
        state_path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        saved = json.loads(state_path.read_text())
        saved['settings']['communication_profile'] = 'custom'
        state_path.write_text(json.dumps(saved))
        self.assertEqual(self.state()['settings']['communication_profile'], 'plain')
        self.assertIn('Communication profile is plain', self.run_cli('render').stdout)
        self.run_cli('set', 'comms', 'custom', ok=False)

    def test_legacy_response_style_migration(self):
        self.run_cli('enable')
        state_path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        original = json.loads(state_path.read_text())
        original['settings']['response_style'] = original['settings'].pop('communication_profile')
        state_path.write_text(json.dumps(original))
        self.assertIn('communication_profile', self.run_cli('settings').stdout)
        self.assertEqual(self.state()['settings']['communication_profile'], 'pyramid')
        self.run_cli('set', 'response_style', 'plain', ok=False)
        self.run_cli('set', 'comms', 'minimal', ok=False)
        self.run_cli('set', 'comms', 'plain')
        self.assertEqual(self.state()['settings']['communication_profile'], 'plain')
        self.run_cli('defaults', 'set', 'communication_profile', 'direct')
        self.assertEqual(self.state(session='new')['settings']['communication_profile'], 'direct')
        self.assertEqual(self.state()['settings']['communication_profile'], 'plain')

    def test_legacy_defaults_migration(self):
        defaults = Path(self.tmp.name) / 'defaults.json'
        defaults.write_text(json.dumps({
            'enabled': False, 'threads': True, 'focus': True,
            'compact': True, 'response_style': 'plain'
        }))
        self.assertEqual(self.state()['settings']['communication_profile'], 'plain')
        self.run_cli('defaults', 'set', 'response_style', 'pyramid', ok=False)
        self.run_cli('defaults', 'set', 'comms', 'pyramid')
        saved = json.loads(defaults.read_text())
        self.assertEqual(saved['communication_profile'], 'pyramid')
        self.assertNotIn('response_style', saved)

    def test_help_and_setup_are_read_only_and_explain_all_options(self):
        help_text = self.run_cli('help').stdout
        for word in ('efficient', 'ste', 'intent', 'full', 'setup', 'threads'):
            self.assertIn(word, help_text)
        # Direct CLI help/setup can run without any session ID.
        for command in ('help', 'setup'):
            process = subprocess.run([sys.executable, str(CLI), '--client', 'codex', command],
                                     env=self.env, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
        overview = self.run_cli('setup').stdout
        for prompt in ('1. Comms', '2. Style', '3. Signals'):
            self.assertIn(prompt, overview)
        self.assertIn('Style ste adds 6 STE-derived guidelines', help_text)
        for output in (help_text, overview, self.run_cli('guidelines', 'list').stdout):
            self.assertNotIn('\u2014', output)
        self.assertFalse(self.state()['settings']['enabled'])
        self.assertEqual(list(Path(self.tmp.name).iterdir()), [])

    def test_setup_applies_all_modes_atomically_and_preserves_activation(self):
        self.run_cli('enable')
        self.run_cli('set', 'threads', 'off')
        self.run_cli('setup', 'apply', '--comms', 'efficient', '--style', 'ste',
                     '--signals', 'full')
        st = self.state()['settings']
        self.assertTrue(st['enabled'])
        self.assertFalse(st['threads'])
        self.assertEqual(st['communication_profile'], 'efficient')
        self.assertEqual(st['language_standard'], 'ste-inspired')
        self.assertEqual(st['signaling'], 'full')
        self.assertNotIn('situation', st)
        saved = (Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json').read_bytes()
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'invalid',
                     '--signals', 'off', ok=False)
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'plain',
                     '--signals', 'invalid', ok=False)
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'plain',
                     ok=False)
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'plain',
                     '--workflow', 'quiet', ok=False)
        self.assertEqual((Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json').read_bytes(), saved)
        self.run_cli('disable')
        self.run_cli('setup', 'apply', '--comms', 'pyramid', '--style', 'plain',
                     '--signals', 'intent')
        self.assertFalse(self.state()['settings']['enabled'])
        self.assertEqual(self.state()['settings']['signaling'], 'intent')

    def test_short_setting_aliases(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'efficient')
        self.run_cli('set', 'style', 'ste')
        self.run_cli('set', 'signals', 'intent')
        values = self.state()['settings']
        self.assertEqual(values['communication_profile'], 'efficient')
        self.assertEqual(values['language_standard'], 'ste-inspired')
        self.assertEqual(values['signaling'], 'intent')
        self.run_cli('defaults', 'set', 'comms', 'direct')
        self.run_cli('defaults', 'set', 'style', 'ste')
        self.assertEqual(self.state(session='new')['settings']['communication_profile'], 'direct')
        self.assertEqual(self.state(session='new')['settings']['language_standard'], 'ste-inspired')

    def test_situations_are_gone(self):
        self.run_cli('enable')
        for refused in (('situations',), ('situation', 'preview', 'sbar'), ('set', 'situation', 'sbar'),
                        ('defaults', 'set', 'situation', 'auto')):
            self.run_cli(*refused, ok=False)
        self.assertNotIn('Situational', self.run_cli('render').stdout)
        self.assertNotIn('sbar', self.run_cli('help').stdout)

    def test_language_and_signals(self):
        self.run_cli('enable')
        self.run_cli('set', 'language_standard', 'ste-inspired')
        self.run_cli('set', 'signaling', 'full')
        rendered = self.run_cli('render').stdout
        self.assertIn('Language standard: ste-inspired', rendered)
        self.assertIn('Response markers:', self.run_cli('signals').stdout)
        self.assertIn('ACK:', rendered)
        self.assertIn('STE', self.run_cli('languages').stdout.upper())
        self.run_cli('set', 'signaling', 'invalid', ok=False)
        self.run_cli('set', 'language_standard', 'invalid', ok=False)
        self.run_cli('set', 'signaling', 'off')
        self.assertNotIn('ACK:', self.run_cli('render').stdout)

    def test_old_session_settings_receive_new_defaults(self):
        self.run_cli('enable')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        for name in ('language_standard', 'signaling'):
            data['settings'].pop(name)
        path.write_text(json.dumps(data))
        settings = self.state()['settings']
        self.assertEqual(settings['language_standard'], 'plain')
        self.assertEqual(settings['signaling'], 'off')

    def test_saved_situation_is_dropped(self):
        self.run_cli('enable')
        self.run_cli('defaults', 'set', 'enabled', 'on')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        defaults = Path(self.tmp.name) / 'defaults.json'
        for saved, settings in ((path, 'settings'), (defaults, None)):
            data = json.loads(saved.read_text())
            (data[settings] if settings else data)['situation'] = 'sbar'
            saved.write_text(json.dumps(data))
        self.assertNotIn('situation', self.state()['settings'])
        self.assertNotIn('situation', self.state(session='new')['settings'])
        self.assertNotIn('Situational', self.run_cli('render').stdout)

    def test_overrides_for_removed_guidelines_are_dropped(self):
        self.run_cli('enable')
        self.run_cli('guideline', 'on', 'warnings')
        self.run_cli('defaults', 'set', 'enabled', 'on')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        defaults = Path(self.tmp.name) / 'defaults.json'
        for saved, settings in ((path, 'settings'), (defaults, None)):
            data = json.loads(saved.read_text())
            (data[settings] if settings else data).setdefault('guideline_overrides', {}).update(
                {'terminology': True, 'notes_not_steps': False, 'formats': True, 'define_terms': True, 'noun_clusters': True, 'one_topic': True})
            saved.write_text(json.dumps(data))
        self.assertEqual(self.state()['settings']['guideline_overrides'], {'warnings': True})
        self.assertEqual(self.state(session='new')['settings']['guideline_overrides'], {})
        self.assertIn('Actionable risk warnings', self.run_cli('render').stdout)

    def test_disabled_fork_replaces_inherited_session_policy(self):
        self.run_cli('enable', session='parent')
        self.run_cli('thread', 'open', 'Parent decision', session='parent')
        parent_path = Path(self.tmp.name) / 'sessions' / 'codex' / 'parent.json'
        saved = parent_path.read_bytes()
        out = self.run_cli('hook', payload={'session_id': 'child', 'source': 'fork'})
        self.assertNotEqual(out.stdout, '')
        context = json.loads(out.stdout)['hookSpecificOutput']['additionalContext']
        self.assertIn('child', context)
        self.assertIn('disabled', context)
        self.assertNotIn('Parent decision', context)
        self.assertFalse(self.state(session='child')['settings']['enabled'])
        self.assertEqual(parent_path.read_bytes(), saved)

    def test_null_records_are_corruption_not_missing_files(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'Keep the ID')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        path.write_text('null')
        self.run_cli('hook', payload={'session_id': 'a', 'source': 'resume'}, ok=False)
        self.assertEqual(path.read_text(), 'null')
        defaults = Path(self.tmp.name) / 'defaults.json'
        defaults.write_text('null')
        self.run_cli('defaults', 'set', 'enabled', 'on', ok=False)
        self.assertEqual(defaults.read_text(), 'null')

    def test_sparse_thread_record_cannot_reuse_a_closed_id(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'One')
        self.run_cli('thread', 'close', '1')
        self.run_cli('thread', 'open', 'Two')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        del data['threads']['1']
        path.write_text(json.dumps(data))
        saved = path.read_bytes()
        self.run_cli('thread', 'open', 'Must not reuse one', ok=False)
        self.assertEqual(path.read_bytes(), saved)

    def test_sparse_option_record_cannot_reuse_a_spent_letter(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'One')
        self.run_cli('thread', 'option', '1', 'First')
        self.run_cli('thread', 'option', '1', 'Second')
        self.run_cli('thread', 'reject', '1', 'b')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        del data['threads']['1']['options']['a']
        path.write_text(json.dumps(data))
        saved = path.read_bytes()
        self.run_cli('thread', 'option', '1', 'Must not overwrite b', ok=False)
        self.assertEqual(path.read_bytes(), saved)

    def test_corrupt_state_is_not_reset(self):
        self.run_cli('enable')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        path.write_text('{broken')
        self.run_cli('enable', ok=False)
        self.assertEqual(path.read_text(), '{broken')

    def test_invalid_settings_and_session_paths_do_not_write(self):
        self.run_cli('set', 'focus', 'sometimes', ok=False)
        self.run_cli('enable', session='../escape', ok=False)
        self.run_cli('set', 'unknown', 'on', ok=False)
        self.assertFalse((Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json').exists())

    def test_disabled_plugin_rejects_thread_mutation(self):
        self.run_cli('thread', 'open', 'Must not activate', ok=False)
        self.assertFalse(self.state()['settings']['enabled'])


if __name__ == '__main__':
    unittest.main()

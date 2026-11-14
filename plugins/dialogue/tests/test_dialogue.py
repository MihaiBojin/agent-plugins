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
                result = self.run_cli('hook', client=client, payload={'session_id': 'a', 'source': source})
                context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
                self.assertIn('Choose storage', context)
                self.assertIn('Need a portable runtime', context)
        self.run_cli('disable', client='codex')
        self.assertTrue(self.state(client='claude')['settings']['enabled'])

    def test_installed_hook_is_silent_until_enabled(self):
        out = self.run_cli('hook', payload={'session_id': 'fresh', 'source': 'startup'})
        self.assertEqual(out.stdout, '')
        self.run_cli('defaults', 'set', 'enabled', 'on')
        out = self.run_cli('hook', payload={'session_id': 'fresh', 'source': 'resume'})
        self.assertEqual(out.stdout, '')

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
            command = config['hooks']['SessionStart'][0]['hooks'][0]['command']
            env = dict(self.env, CLAUDE_PLUGIN_ROOT=str(ROOT), PLUGIN_ROOT=str(ROOT))
            payload = json.dumps({'session_id': 'packaged', 'source': 'startup'})
            result = subprocess.run(['bash', '-c', command], env=env, input=payload,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')
            self.run_cli('enable', session='packaged', client=client)
            result = subprocess.run(['bash', '-c', command], env=env, input=payload,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
            self.assertIn(client + ' session packaged', context)

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
        self.assertIn('(14/35 enabled)', enabled)
        self.assertIn('No routine narration', enabled)
        self.assertIn('## Communication profile: direct', self.run_cli('render').stdout)
        self.run_cli('set', 'communication_profile', 'efficient')
        self.assertIn('(11/35 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'plain')
        self.assertIn('(0/35 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'invalid', ok=False)

    def test_pyramid_renders_the_rules_it_selects(self):
        self.run_cli('enable')
        rendered = self.run_cli('render').stdout
        for text in ('- Verdict first: For implementation questions',
                     'reasons that do not overlap and together cover it',
                     '- One recommendation:', '- Tables for comparisons:', '- No preamble or recap:',
                     '- Current state:', '- One question at a time:', '- Plain punctuation: No em-dashes',
                     '- Defined terms:', '- Clear pronouns:', 'Name the actor, or say it is unknown.',
                     'unknowns and proposals; name missing evidence'):
            self.assertIn(text, rendered)
        self.assertNotIn('Short routine replies', rendered)
        profiles = json.loads((ROOT / 'skills' / 'dialogue' / 'profiles.json').read_text())
        self.assertFalse(any('instruction' in profile for profile in profiles.values()))
        self.run_cli('set', 'comms', 'efficient')
        self.assertIn('- Short routine replies: Routine replies take one to three sentences.',
                      self.run_cli('render').stdout)

    def test_risk_levels_come_from_one_definition(self):
        self.run_cli('enable')
        self.assertNotIn('Risk levels:', self.run_cli('render').stdout)
        signals = json.loads((ROOT / 'skills' / 'dialogue' / 'signals.json').read_text())
        meanings = {item['id']: item['meaning'] for item in signals['intents']}
        self.assertNotIn('RISK', meanings)
        levels = '\n'.join(['Risk levels:', f"- WARNING: {meanings['WARNING']}", f"- CAUTION: {meanings['CAUTION']}"])
        self.run_cli('set', 'situation', 'ipass')
        rendered = self.run_cli('render').stdout
        self.assertIn('stable, CAUTION, or WARNING', rendered)
        self.assertIn(levels, rendered)
        for name in ('methane', 'cus'):
            self.assertIn(levels, self.run_cli('situation', 'preview', name).stdout)
        self.assertNotIn('Risk levels:', self.run_cli('situation', 'preview', 'sbar').stdout)
        self.run_cli('set', 'situation', 'none')
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
        self.assertIn('one_action [off, profile]', all_rules)
        groups = self.run_cli('guidelines', 'group', 'list').stdout
        self.assertIn('brevity: 3/6 enabled', groups)
        self.assertNotIn('\\n', groups)
        self.assertEqual(len(groups.splitlines()), 9)
        assert_group = self.run_cli('guidelines', 'group', 'list', 'procedures').stdout
        self.assertIn('one_action', assert_group)
        self.assertNotIn('bluf', assert_group)
        self.run_cli('guideline', 'group', 'enable', 'procedures')
        self.assertIn('one_action [on, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'disable', 'terminology')
        self.assertIn('terminology [off, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'enable', 'terminology')
        self.assertIn('terminology [on, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'reset', 'terminology')
        self.assertIn('terminology [off, profile]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'disable', 'procedures')
        self.assertIn('one_action [off, override]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'reset', 'procedures')
        self.assertIn('one_action [off, profile]', self.run_cli('guidelines', 'list').stdout)
        self.run_cli('guideline', 'group', 'enable', 'invalid', ok=False)
        self.run_cli('guidelines', 'group', 'list', 'invalid', ok=False)
        self.run_cli('guideline', 'group', 'enable', ok=False)

    def test_guideline_legacy_forms_still_work(self):
        self.run_cli('enable')
        self.run_cli('guideline', 'on', 'terminology')
        self.assertIn('terminology [on, override]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'group', 'brevity', 'off')
        self.assertIn('sufficient [off, override]', self.run_cli('guidelines', '--all', '--group', 'brevity').stdout)
        self.run_cli('guideline', 'group', 'brevity', 'reset')
        self.assertIn('sufficient [on, profile]', self.run_cli('guidelines', 'list').stdout)

    def test_guideline_individual_and_group_overrides(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'custom')
        self.assertIn('(0/35 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'on', 'bluf')
        self.assertIn('BLUF', self.run_cli('render').stdout)
        self.assertIn('(1/35 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'off', 'bluf')
        self.assertIn('(0/35 enabled)', self.run_cli('guidelines').stdout)
        self.run_cli('guideline', 'reset', 'bluf')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.run_cli('guideline', 'group', 'procedures', 'on')
        enabled = self.run_cli('guidelines', '--group', 'procedures').stdout
        self.assertIn('one_action', enabled)
        self.assertNotIn('bluf', enabled)
        self.assertEqual(len(self.state()['settings']['guideline_overrides']), 5)
        self.run_cli('guideline', 'group', 'procedures', 'reset')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.assertIn('one_action [off, profile]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'group', 'invalid', 'on', ok=False)
        self.run_cli('guideline', 'on', 'missing', ok=False)
        self.run_cli('guideline', 'on', 'bluf', 'off', ok=False)

    def test_guideline_overrides_persist_across_sessions_and_upgrade(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'plain')
        self.run_cli('guideline', 'on', 'terminology')
        self.assertIn('Consistent terminology', self.run_cli('render').stdout)
        for source in ('resume', 'compact'):
            result = self.run_cli('hook', payload={'session_id': 'a', 'source': source})
            rendered = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
            self.assertIn('Consistent terminology', rendered)
        self.run_cli('set', 'comms', 'efficient')
        self.assertTrue(self.state()['settings']['guideline_overrides']['terminology'])
        self.run_cli('guideline', 'reset', 'all')
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})
        self.assertNotIn('Consistent terminology', self.run_cli('render').stdout)
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        del data['settings']['guideline_overrides']
        path.write_text(json.dumps(data))
        self.assertEqual(self.state()['settings']['guideline_overrides'], {})

    def test_ste_style_rules_can_be_overridden(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'custom')
        self.run_cli('set', 'style', 'ste')
        self.assertIn('(13/35 enabled)', self.run_cli('guidelines').stdout)
        self.assertIn('terminology [on, style]', self.run_cli('guidelines', '--all').stdout)
        self.run_cli('guideline', 'off', 'terminology')
        enabled = self.run_cli('guidelines', '--all').stdout
        self.assertIn('terminology [off, override]', enabled)
        self.assertNotIn('Consistent terminology', self.run_cli('render').stdout)
        self.run_cli('guideline', 'reset', 'terminology')
        self.assertIn('terminology [on, style]', self.run_cli('guidelines', '--all').stdout)

    def test_default_guideline_overrides_apply_only_to_new_sessions(self):
        self.run_cli('enable')
        self.run_cli('guideline', '--default', 'on', 'one_action')
        self.run_cli('guideline', '--default', 'group', 'brevity', 'off')
        current = self.state()['settings']
        self.assertEqual(current['guideline_overrides'], {})
        future = self.state(session='future')['settings']['guideline_overrides']
        self.assertTrue(future['one_action'])
        self.assertFalse(future['sufficient'])
        self.run_cli('guideline', '--default', 'reset', 'one_action')
        later = self.state(session='later')['settings']['guideline_overrides']
        self.assertNotIn('one_action', later)
        self.assertIn('one_action', future)
        self.assertNotIn('one_action', current['guideline_overrides'])

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
        for word in ('efficient', 'ste', 'sbar', 'ipass', 'can', 'cus',
                     'methane', 'intent', 'full', 'setup', 'threads'):
            self.assertIn(word, help_text)
        # Direct CLI help/setup can run without any session ID.
        for command in ('help', 'setup'):
            process = subprocess.run([sys.executable, str(CLI), '--client', 'codex', command],
                                     env=self.env, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
        overview = self.run_cli('setup').stdout
        for prompt in ('1. Comms', '2. Style', '3. Workflow'):
            self.assertIn(prompt, overview)
        self.assertIn('Style ste adds 13 STE-derived guidelines', help_text)
        for output in (help_text, overview, self.run_cli('guidelines', 'list').stdout):
            self.assertNotIn('\u2014', output)
        self.assertFalse(self.state()['settings']['enabled'])
        self.assertEqual(list(Path(self.tmp.name).iterdir()), [])

    def test_setup_applies_all_modes_atomically_and_preserves_activation(self):
        self.run_cli('enable')
        self.run_cli('set', 'threads', 'off')
        self.run_cli('setup', 'apply', '--comms', 'efficient', '--style', 'ste',
                     '--workflow', 'handoff')
        st = self.state()['settings']
        self.assertTrue(st['enabled'])
        self.assertFalse(st['threads'])
        self.assertEqual(st['communication_profile'], 'efficient')
        self.assertEqual(st['language_standard'], 'ste-inspired')
        self.assertEqual(st['situation'], 'ipass')
        self.assertEqual(st['signaling'], 'full')
        saved = (Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json').read_bytes()
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'invalid',
                     '--workflow', 'quiet', ok=False)
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'plain',
                     '--workflow', 'invalid', ok=False)
        self.run_cli('setup', 'apply', '--comms', 'plain', '--style', 'plain',
                     ok=False)
        self.assertEqual((Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json').read_bytes(), saved)
        self.run_cli('disable')
        self.run_cli('setup', 'apply', '--comms', 'pyramid', '--style', 'plain',
                     '--workflow', 'automatic')
        self.assertFalse(self.state()['settings']['enabled'])
        self.assertEqual(self.state()['settings']['situation'], 'auto')

    def test_short_setting_aliases(self):
        self.run_cli('enable')
        self.run_cli('set', 'comms', 'efficient')
        self.run_cli('set', 'style', 'ste')
        self.run_cli('set', 'situation', 'sbar')
        self.run_cli('set', 'signals', 'intent')
        values = self.state()['settings']
        self.assertEqual(values['communication_profile'], 'efficient')
        self.assertEqual(values['language_standard'], 'ste-inspired')
        self.assertEqual(values['situation'], 'sbar')
        self.assertEqual(values['signaling'], 'intent')
        self.run_cli('defaults', 'set', 'comms', 'direct')
        self.run_cli('defaults', 'set', 'style', 'ste')
        self.assertEqual(self.state(session='new')['settings']['communication_profile'], 'direct')
        self.assertEqual(self.state(session='new')['settings']['language_standard'], 'ste-inspired')

    def test_situations_preview_and_selection(self):
        self.run_cli('enable')
        self.assertIn('sbar', self.run_cli('situations').stdout)
        preview = self.run_cli('situation', 'preview', 'sbar').stdout
        self.assertIn('Situation:', preview)
        self.assertEqual(self.state()['settings']['situation'], 'none')
        self.run_cli('situation', 'use', 'ipass')
        self.assertEqual(self.state()['settings']['situation'], 'ipass')
        self.assertIn('Synthesis by receiver', self.run_cli('render').stdout)
        for client in ('codex', 'claude'):
            self.run_cli('enable', client=client)
            self.run_cli('situation', 'use', 'can', client=client)
            for source in ('resume', 'compact'):
                result = self.run_cli('hook', client=client,
                                      payload={'session_id': 'a', 'source': source})
                context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
                self.assertIn('Situational framework: can', context)
        self.run_cli('situation', 'clear')
        self.assertNotIn('Situational framework: can', self.run_cli('render').stdout)
        self.run_cli('situation', 'preview', 'invalid', ok=False)

    def test_auto_situations_and_language_signals(self):
        self.run_cli('enable')
        self.run_cli('set', 'situation', 'auto')
        self.run_cli('set', 'language_standard', 'ste-inspired')
        self.run_cli('set', 'signaling', 'full')
        rendered = self.run_cli('render').stdout
        self.assertIn('Situational mode: auto', rendered)
        self.assertIn('Language standard: ste-inspired', rendered)
        self.assertIn('Response markers:', self.run_cli('signals').stdout)
        self.assertIn('ACK:', rendered)
        self.assertIn('STE', self.run_cli('languages').stdout.upper())
        self.run_cli('set', 'signaling', 'invalid', ok=False)
        self.run_cli('set', 'language_standard', 'invalid', ok=False)
        self.run_cli('set', 'situation', 'invalid', ok=False)
        self.run_cli('set', 'signaling', 'off')
        self.assertNotIn('ACK:', self.run_cli('render').stdout)

    def test_old_session_settings_receive_new_defaults(self):
        self.run_cli('enable')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        for name in ('situation', 'language_standard', 'signaling'):
            data['settings'].pop(name)
        path.write_text(json.dumps(data))
        settings = self.state()['settings']
        self.assertEqual(settings['situation'], 'none')
        self.assertEqual(settings['language_standard'], 'plain')
        self.assertEqual(settings['signaling'], 'off')
        self.run_cli('set', 'situation', 'sbar')
        self.assertEqual(self.state()['settings']['situation'], 'sbar')

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

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
        self.run_cli('thread', 'open', 'Child', '--parent', '1')
        self.run_cli('thread', 'option', '1', 'Python')
        self.run_cli('thread', 'option', '1', 'Bash')
        self.run_cli('thread', 'reject', '1', 'a')
        self.run_cli('thread', 'option', '1', 'Node')
        result = self.run_cli('thread', 'show', '1').stdout
        self.assertNotIn('1a/', result)
        self.assertIn('1c/', result)
        self.run_cli('thread', 'choose', '1', 'b')
        records = self.state()['threads']
        self.assertEqual(records['1']['status'], 'closed')
        self.assertEqual(records['1.1']['status'], 'closed')
        self.run_cli('thread', 'reopen', '1.1')
        self.assertEqual(self.state()['threads']['1']['status'], 'open')
        self.run_cli('thread', 'open', 'Two')
        self.assertIn('2', self.state()['threads'])

    def test_focus_compact_and_audit_preserve_hidden_threads(self):
        self.run_cli('enable')
        self.run_cli('thread', 'open', 'First')
        self.run_cli('thread', 'open', 'Second')
        rendered = self.run_cli('render').stdout
        self.assertIn('First', rendered)
        self.assertNotIn('## 2/ Second', rendered)
        self.assertIn('1 other open thread', rendered)
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
        self.assertNotIn('## 1/ Kept', out)
        self.assertIn('## Communication profile: pyramid', out)
        self.run_cli('thread', 'open', 'No', ok=False)
        self.run_cli('set', 'threads', 'on')
        out = self.run_cli('set', 'response_style', 'plain').stdout
        self.assertIn('## 1/ Kept', out)
        self.assertNotIn('## Communication profile: pyramid', out)

    def test_communication_profiles_and_guidelines(self):
        self.assertIn('no guidelines are active', self.run_cli('guidelines').stdout)
        self.run_cli('enable')
        self.assertIn('pyramid', self.run_cli('profiles').stdout)
        self.assertIn('BLUF', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'direct')
        self.assertEqual(self.state()['settings']['communication_profile'], 'direct')
        enabled = self.run_cli('guidelines').stdout
        self.assertIn('(12/12)', enabled)
        self.assertIn('No routine narration', enabled)
        self.assertIn('## Communication profile: direct', self.run_cli('render').stdout)
        self.run_cli('set', 'communication_profile', 'efficient')
        self.assertIn('(8/12)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'plain')
        self.assertIn('(0/12)', self.run_cli('guidelines').stdout)
        self.run_cli('set', 'communication_profile', 'invalid', ok=False)

    def test_legacy_response_style_migration(self):
        self.run_cli('enable')
        state_path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        original = json.loads(state_path.read_text())
        original['settings']['response_style'] = original['settings'].pop('communication_profile')
        state_path.write_text(json.dumps(original))
        self.assertIn('communication_profile', self.run_cli('settings').stdout)
        self.assertEqual(self.state()['settings']['communication_profile'], 'pyramid')
        self.run_cli('set', 'response_style', 'plain')
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
        self.run_cli('defaults', 'set', 'response_style', 'pyramid')
        saved = json.loads(defaults.read_text())
        self.assertEqual(saved['communication_profile'], 'pyramid')
        self.assertNotIn('response_style', saved)

    def test_minimal_profile_migrates_to_efficient(self):
        self.run_cli('enable')
        path = Path(self.tmp.name) / 'sessions' / 'codex' / 'a.json'
        data = json.loads(path.read_text())
        data['settings']['communication_profile'] = 'minimal'
        path.write_text(json.dumps(data))
        self.assertEqual(self.state()['settings']['communication_profile'], 'efficient')

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

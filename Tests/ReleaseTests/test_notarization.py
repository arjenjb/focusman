"""Exercise release scripts without signing, uploading, or using real credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TOOL_LOG'], 'a') as log:
    log.write(json.dumps([name] + args) + '\n')
if name == 'codesign' and '-d' in args:
    print(os.environ.get('FAKE_SIGNATURE', 'Authority=Developer ID Application: Fixture (TESTTEAM)'))
elif name == 'xcrun':
    if args[:2] == ['notarytool', 'submit']:
        print(json.dumps({'status': os.environ.get('FAKE_STATUS', 'Accepted'), 'id': 'fixture-submission'}))
        sys.exit(int(os.environ.get('FAKE_SUBMIT_EXIT', '0')))
    elif args[:2] == ['notarytool', 'log']:
        pathlib.Path(args[-1]).write_text('{"issues": []}')
    elif args[:2] == ['stapler', 'staple']:
        sys.exit(int(os.environ.get('FAKE_STAPLE_EXIT', '0')))
'''


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='focusman-notary-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(PROJECT / 'Scripts', self.root / 'Scripts')
        (self.root / 'build/Focusman.app').mkdir(parents=True)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for tool in ['codesign', 'xcrun', 'ditto', 'make']:
            path = self.bin / tool
            path.write_text(FAKE_TOOL)
            path.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('NOTARY_', 'NOTARIZE_', 'SIGN_IDENTITY', 'FAKE_'))}
        self.env.update(PATH=str(self.bin) + ':' + os.environ['PATH'],
                        TOOL_LOG=str(self.root / 'tools.jsonl'),
                        NOTARY_REPORT_DIR=str(self.root / 'reports with spaces'))

    def run_script(self, script='notarize.sh', arguments=None, **env):
        return subprocess.run(['bash', str(self.root / 'Scripts' / script)] + (arguments or []),
                              cwd=self.root, env={**self.env, **env}, text=True, capture_output=True)

    def calls(self):
        path = self.root / 'tools.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_acceptance_staples_and_validates_before_success(self):
        result = self.run_script(NOTARY_KEYCHAIN_PROFILE='fixture profile')
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = [call[:3] for call in self.calls() if call[0] == 'xcrun']
        self.assertEqual(operations, [['xcrun', 'notarytool', 'submit'],
                                     ['xcrun', 'stapler', 'staple'],
                                     ['xcrun', 'stapler', 'validate']])
        submit = next(c for c in self.calls() if c[:3] == ['xcrun', 'notarytool', 'submit'])
        self.assertIn('fixture profile', submit)
        self.assertIn('--wait', submit)

    def test_rejection_with_zero_exit_status_still_fails(self):
        result = self.run_script(NOTARY_KEYCHAIN_PROFILE='fixture', FAKE_STATUS='Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any(c[:3] == ['xcrun', 'notarytool', 'log'] for c in self.calls()))
        self.assertFalse(any(c[:2] == ['xcrun', 'stapler'] for c in self.calls()))

    def test_timeout_never_staples(self):
        result = self.run_script(NOTARY_KEYCHAIN_PROFILE='fixture', FAKE_STATUS='In Progress', FAKE_SUBMIT_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fixture-submission', result.stderr)
        self.assertFalse(any(c[:2] == ['xcrun', 'stapler'] for c in self.calls()))

    def test_stapling_failure_stops_release(self):
        result = self.run_script(NOTARY_KEYCHAIN_PROFILE='fixture', FAKE_STAPLE_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[:3] == ['xcrun', 'stapler', 'validate'] for c in self.calls()))

    def test_team_api_key_credentials(self):
        key = self.root / 'key with spaces.p8'
        key.write_text('test fixture, not a credential')
        result = self.run_script(NOTARY_KEY_PATH=str(key), NOTARY_KEY_ID='fixture-key', NOTARY_ISSUER_ID='fixture-issuer')
        self.assertEqual(result.returncode, 0, result.stderr)
        submit = next(c for c in self.calls() if c[:3] == ['xcrun', 'notarytool', 'submit'])
        self.assertIn(str(key), submit)
        self.assertIn('--issuer', submit)
        self.assertNotIn('--keychain-profile', submit)

    def test_missing_credentials_fail_before_build(self):
        result = self.run_script('release.sh', ['1.2.3', 'false'])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_ad_hoc_signature_cannot_be_submitted(self):
        result = self.run_script(NOTARY_KEYCHAIN_PROFILE='fixture', FAKE_SIGNATURE='Signature=adhoc')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == 'xcrun' for c in self.calls()))

    def test_snapshot_needs_no_credentials_or_notarization(self):
        result = self.run_script('release.sh', ['1.2.3', 'true'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(c[0] == 'make' for c in self.calls()))
        self.assertFalse(any(c[0] == 'xcrun' for c in self.calls()))

    def test_release_and_opted_in_snapshot_both_notarize(self):
        for snapshot in ['false', 'true']:
            with self.subTest(snapshot=snapshot):
                (self.root / 'tools.jsonl').write_text('')
                result = self.run_script('release.sh', ['1.2.3', snapshot],
                                         NOTARY_KEYCHAIN_PROFILE='fixture', NOTARIZE_SNAPSHOT='1')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls()[0][0], 'make')
                self.assertTrue(any(c[:3] == ['xcrun', 'stapler', 'validate'] for c in self.calls()))


if __name__ == '__main__':
    unittest.main()

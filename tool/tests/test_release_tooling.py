import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from android_signing import prepare, property_value
from release_assets import collect
from release_policy import REPOSITORY, validate


class ReleasePolicyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Release test')
        self.git('config', 'user.email', 'release@example.invalid')
        self.git('commit', '--allow-empty', '-qm', 'stable')
        self.stable = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/master', self.stable)
        self.git('tag', '-a', 'v1.14.1', '-m', 'stable')
        self.git('commit', '--allow-empty', '-qm', 'dev')
        self.dev = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/dev', self.dev)
        self.git('tag', 'dev_v1.14.1')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def check(self, tag, commit, repository=REPOSITORY, version='1.14.1+11402'):
        self.git('checkout', '-q', '--detach', commit)
        return validate(repository, tag, version, commit, self.root)

    def test_stable_annotated_tag_and_dev_lightweight_tag(self):
        self.assertEqual(self.check('v1.14.1', self.stable), 'stable')
        self.assertEqual(self.check('dev_v1.14.1', self.dev), 'dev')

    def test_stable_ancestor_of_master_is_allowed(self):
        self.git('update-ref', 'refs/remotes/origin/master', self.dev)
        self.assertEqual(self.check('v1.14.1', self.stable), 'stable')

    def test_dev_commit_not_promoted_to_master_is_rejected(self):
        self.git('tag', '-f', 'v1.14.1', self.dev)
        with self.assertRaisesRegex(ValueError, 'origin/master'):
            self.check('v1.14.1', self.dev)

    def test_wrong_fork_identity_rejected(self):
        with self.assertRaisesRegex(ValueError, 'maintained only'):
            self.check('dev_v1.14.1', self.dev, repository='xiaoyaocz/dart_simple_live')

    def test_mismatched_version_and_noncanonical_tags_rejected(self):
        for tag in ('v1.14.0', 'v01.14.1', 'dev_v1.14.1-rc', 'v1.14.1+11402'):
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, 'exactly match'):
                self.check(tag, self.dev)

    def test_tag_and_checkout_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, 'same commit'):
            self.check('v1.14.1', self.dev)

    def test_missing_branch_ref_rejected(self):
        self.git('update-ref', '-d', 'refs/remotes/origin/dev')
        with self.assertRaisesRegex(ValueError, 'origin/dev'):
            self.check('dev_v1.14.1', self.dev)

    def test_event_sha_and_checkout_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, 'same commit'):
            validate(REPOSITORY, 'dev_v1.14.1', '1.14.1+11402', self.stable, self.root)


class AndroidSigningTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'simple_live_app/android').mkdir(parents=True)
        self.properties = self.root / 'simple_live_app/android/key.properties'
        self.environment = {'BUILD_EVENT': 'push', 'KEYSTORE_BASE64': base64.b64encode(b'fake test keystore').decode(),
                            'STORE_PASSWORD': 'secret\nwith=special\\chars', 'KEY_PASSWORD': '密码', 'KEY_ALIAS': 'test'}

    def test_pr_never_uses_keys_and_removes_existing_properties(self):
        self.properties.write_text('old=private')
        self.environment['BUILD_EVENT'] = 'pull_request'
        self.assertEqual(prepare(self.root, self.environment), 'unsigned')
        self.assertFalse(self.properties.exists())
        self.assertFalse((self.properties.parent / 'ci-keystore.jks').exists())

    def test_missing_secret_fails_without_writing_key(self):
        del self.environment['KEY_PASSWORD']
        with self.assertRaisesRegex(ValueError, 'KEY_PASSWORD'):
            prepare(self.root, self.environment)
        self.assertFalse(self.properties.exists())

    def test_invalid_base64_fails_without_echoing_secret(self):
        self.environment['KEYSTORE_BASE64'] = 'PRIVATE!SECRET!'
        with self.assertRaisesRegex(ValueError, 'valid base64') as error:
            prepare(self.root, self.environment)
        self.assertNotIn('PRIVATE', str(error.exception))

    def test_wrapped_base64_and_property_escaping(self):
        key = self.environment['KEYSTORE_BASE64']
        self.environment['KEYSTORE_BASE64'] = key[:8] + '\n' + key[8:]
        self.assertEqual(prepare(self.root, self.environment), 'signed')
        properties = self.properties.read_text()
        self.assertEqual(len(properties.splitlines()), 4)
        self.assertIn('secret\\nwith\\=special\\\\chars', properties)
        self.assertIn('keyPassword=\\u5bc6\\u7801', properties)
        self.assertEqual((self.properties.parent / 'ci-keystore.jks').read_bytes(), b'fake test keystore')

    def test_supplementary_unicode_is_java_surrogate_pair(self):
        self.assertEqual(property_value('😀'), '\\ud83d\\ude00')


class ReleaseAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.artifacts = self.root / 'artifacts'
        self.output = self.root / 'release'
        for name, files in {'android-apk': ['app-arm64-v8a-release.apk', 'app-armeabi-v7a-release.apk', 'app-x86_64-release.apk'],
                            'windows-portable': ['SimpleLive-1.14.1+11402-Windows-Portable.zip'],
                            'windows-msix': ['simple_live_app-1.14.1+11402-windows.msix']}.items():
            folder = self.artifacts / name
            folder.mkdir(parents=True)
            for filename in files:
                (folder / filename).write_bytes(filename.encode())
        self.status = self.artifacts / 'android-apk/SIGNING_STATUS.txt'
        self.status.write_text('SIGNED BUILD: test only\n')
        self.metadata = {'repository': REPOSITORY, 'sha': 'a' * 40, 'version': '1.14.1+11402', 'channel': 'stable'}

    def test_complete_assets_and_hashes_include_metadata(self):
        collect(self.artifacts, self.output, self.metadata)
        self.assertEqual(json.loads((self.output / 'BUILD_INFO.json').read_text()), self.metadata)
        lines = (self.output / 'SHA256SUMS').read_text().splitlines()
        self.assertEqual(len(lines), 6)
        for line in lines:
            digest, filename = line.split('  ')
            self.assertEqual(digest, hashlib.sha256((self.output / filename).read_bytes()).hexdigest())

    def test_missing_platform_artifact_prevents_draft(self):
        next((self.artifacts / 'windows-msix').iterdir()).unlink()
        with self.assertRaisesRegex(ValueError, 'windows-msix'):
            collect(self.artifacts, self.output, self.metadata)
        self.assertFalse(self.output.exists())

    def test_unsigned_apks_prevent_draft(self):
        self.status.write_text('UNSIGNED PR BUILD: test\n')
        with self.assertRaisesRegex(ValueError, 'signed build'):
            collect(self.artifacts, self.output, self.metadata)

    def test_empty_assets_prevent_draft(self):
        next((self.artifacts / 'windows-msix').iterdir()).write_bytes(b'')
        with self.assertRaisesRegex(ValueError, 'empty'):
            collect(self.artifacts, self.output, self.metadata)

    def test_existing_output_is_not_overwritten(self):
        self.output.mkdir()
        (self.output / 'existing').write_text('keep')
        with self.assertRaisesRegex(ValueError, 'empty'):
            collect(self.artifacts, self.output, self.metadata)
        self.assertEqual((self.output / 'existing').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()

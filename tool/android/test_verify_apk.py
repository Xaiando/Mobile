"""Tests for verify_apk.py. Run from the repository root:

    python -m unittest discover -s tool/android -p "test_*.py"
"""
import hashlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import verify_apk  # noqa: E402

TESTDATA = Path(__file__).parent / 'testdata'
# The compiled manifest of the CI release APK built from commit 154a2a5,
# before the release manifest removed INTERNET.
REAL_MANIFEST = (TESTDATA / 'AndroidManifest-0.4.0-154a2a5.bin').read_bytes()


def elf64(*alignments: int) -> bytes:
    """A minimal 64-bit little-endian ELF with one PT_LOAD per alignment."""
    header = bytearray(64)
    header[:4] = b'\x7fELF'
    header[4], header[5] = 2, 1
    struct.pack_into('<Q', header, 0x20, 64)           # e_phoff
    struct.pack_into('<HH', header, 0x36, 56, len(alignments))  # phentsize, phnum
    body = bytearray()
    for align in alignments:
        entry = bytearray(56)
        struct.pack_into('<I', entry, 0, 1)            # PT_LOAD
        struct.pack_into('<Q', entry, 0x30, align)     # p_align
        body += entry
    return bytes(header + body)


def length_prefixed(data: bytes) -> bytes:
    return struct.pack('<I', len(data)) + data


def signing_block(certificate: bytes, pair_id: int = 0x7109871A) -> bytes:
    signed_data = length_prefixed(b'') + length_prefixed(length_prefixed(certificate))
    signer = length_prefixed(signed_data)
    value = length_prefixed(length_prefixed(signer))
    pair = struct.pack('<QI', len(value) + 4, pair_id) + value
    size = len(pair) + 8 + 16  # the size field again and the magic
    return struct.pack('<Q', size) + pair + struct.pack('<Q', size) + b'APK Sig Block 42'


def make_apk(path: Path, *, manifest=REAL_MANIFEST, libs=None, aligned=True,
             certificate: bytes | None = b'CERTIFICATE-DER') -> None:
    """Writes a small APK: stored libraries padded to 16 KB when [aligned]."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.writestr('AndroidManifest.xml', manifest)
        for name, blob in (libs or {}).items():
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_STORED
            if aligned:
                start = buffer.tell() + 30 + len(name)
                info.extra = b'\x00' * ((-start) % 16384)
            archive.writestr(info, blob)
    data = bytearray(buffer.getvalue())
    if certificate is not None:
        eocd = data.rfind(b'PK\x05\x06')
        directory = struct.unpack_from('<I', data, eocd + 16)[0]
        block = signing_block(certificate)
        data[directory:directory] = block
        struct.pack_into('<I', data, eocd + len(block) + 16, directory + len(block))
    path.write_bytes(bytes(data))


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.manifest = verify_apk.parse_manifest(REAL_MANIFEST)

    def test_reads_the_real_compiled_manifest(self):
        result = verify_apk.Result()
        verify_apk.check_manifest(self.manifest, result, debug=False)
        self.assertEqual(result.facts['package'], 'com.xaiando.sommelier')
        self.assertEqual(result.facts['versionName'], '0.4.0')
        self.assertEqual(result.facts['versionCode'], 17)
        self.assertEqual(result.facts['minSdk'], 24)
        self.assertEqual(result.facts['targetSdk'], 36)
        self.assertEqual(result.facts['permissions'], [
            'android.permission.ACCESS_NETWORK_STATE',
            'android.permission.INTERNET',
            'com.xaiando.sommelier.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
        ])
        self.assertEqual(result.facts['extractNativeLibs'], False)

    def test_a_release_build_may_not_hold_internet(self):
        result = verify_apk.Result()
        verify_apk.check_manifest(self.manifest, result, debug=False)
        self.assertEqual(len(result.problems), 1, result.problems)
        self.assertIn('android.permission.INTERNET is not allowed', result.problems[0])
        self.assertIn('src/release/AndroidManifest.xml', result.problems[0])

    def test_a_debug_build_may(self):
        result = verify_apk.Result()
        verify_apk.check_manifest(self.manifest, result, debug=True)
        self.assertEqual(result.problems, [])

    def test_a_required_permission_must_be_present(self):
        result = verify_apk.Result()
        verify_apk.check_manifest(
            self.manifest, result, debug=True,
            required=('android.permission.INTERNET', 'android.permission.CAMERA'))
        self.assertEqual(result.problems, [
            'permission android.permission.CAMERA is required but missing'])

    def test_finds_the_activities_and_backup_rules(self):
        application = next(self.manifest.find_all('application'))
        self.assertIsNotNone(application.android('fullBackupContent'))
        self.assertIsNotNone(application.android('dataExtractionRules'))
        names = {a.android('name') for a in self.manifest.find_all('activity')}
        self.assertIn('com.xaiando.sommelier.MainActivity', names)

    def test_refuses_what_is_not_binary_xml(self):
        with self.assertRaises(verify_apk.ApkError):
            verify_apk.parse_manifest(b'<manifest/>')


class LibraryTest(unittest.TestCase):
    def check(self, libs, *, aligned=True) -> verify_apk.Result:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'app.apk'
            make_apk(path, libs=libs, aligned=aligned)
            data = path.read_bytes()
            result = verify_apk.Result()
            verify_apk.check_native_libraries(data, zipfile.ZipFile(path), result)
            return result

    def test_accepts_16_kb_segments_at_aligned_offsets(self):
        result = self.check({'lib/arm64-v8a/libgood.so': elf64(0x4000, 0x10000)})
        self.assertEqual(result.problems, [])
        self.assertEqual(result.facts['libraries16kbChecked'], 1)

    def test_rejects_a_4_kb_segment(self):
        result = self.check({'lib/arm64-v8a/libold.so': elf64(0x4000, 0x1000)})
        self.assertEqual(len(result.problems), 1)
        self.assertIn('aligned to 4096', result.problems[0])

    def test_rejects_an_entry_that_is_not_16_kb_aligned(self):
        result = self.check({'lib/x86_64/libgood.so': elf64(0x4000)}, aligned=False)
        self.assertTrue(any('not 16 KB-aligned in the APK' in p for p in result.problems),
                        result.problems)

    def test_32_bit_libraries_are_not_held_to_16_kb(self):
        result = self.check({'lib/armeabi-v7a/libold.so': b'not an elf'})
        self.assertEqual(result.problems, [])
        self.assertEqual(result.facts['abis'], {'armeabi-v7a': 1})

    def test_rejects_a_64_bit_library_that_is_not_elf64(self):
        result = self.check({'lib/arm64-v8a/libbad.so': b'garbage'})
        self.assertIn('not a 64-bit ELF library', result.problems[0])


class SigningTest(unittest.TestCase):
    def test_reads_the_scheme_and_certificate_fingerprint(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'app.apk'
            make_apk(path, certificate=b'CERTIFICATE-DER')
            result = verify_apk.Result()
            verify_apk.check_signing(path.read_bytes(), zipfile.ZipFile(path), result)
        self.assertEqual(result.problems, [])
        self.assertEqual(result.facts['signatureSchemes'], ['v2'])
        self.assertEqual(result.facts['certificateSha256'],
                         [hashlib.sha256(b'CERTIFICATE-DER').hexdigest().upper()])

    def test_knows_the_throwaway_debug_key_from_any_other(self):
        facts = {}
        for name, certificate in (('debug', b'0' + b'CN=Android Debug,O=Android,C=US'),
                                  ('release', b'0' + b'CN=Sommelier Study Companion, O=Xaiando')):
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'app.apk'
                make_apk(path, certificate=certificate)
                result = verify_apk.Result()
                verify_apk.check_signing(path.read_bytes(), zipfile.ZipFile(path), result)
            self.assertEqual(result.problems, [])
            facts[name] = result.facts['signedWithDebugKey']
        self.assertEqual(facts, {'debug': True, 'release': False})

    def test_an_unsigned_apk_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'app.apk'
            make_apk(path, certificate=None)
            result = verify_apk.Result()
            verify_apk.check_signing(path.read_bytes(), zipfile.ZipFile(path), result)
        self.assertEqual(result.problems, ['the APK has no v2 or later signature'])


class CommandLineTest(unittest.TestCase):
    def run_main(self, path, *flags):
        output = io.StringIO()
        saved, sys.stdout = sys.stdout, output
        try:
            code = verify_apk.main([str(path), *flags])
        finally:
            sys.stdout = saved
        return code, output.getvalue()

    def test_exit_codes_and_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'app.apk'
            make_apk(path, libs={'lib/arm64-v8a/libgood.so': elf64(0x4000)})
            code, text = self.run_main(path)
            self.assertEqual(code, 1)
            self.assertIn('FAIL permission android.permission.INTERNET', text)
            code, text = self.run_main(path, '--debug')
            self.assertEqual(code, 0)
            self.assertIn('OK: every check passed.', text)
            code, text = self.run_main(
                path, '--debug', '--require-permission', 'android.permission.INTERNET')
            self.assertEqual(code, 0)
            code, text = self.run_main(
                path, '--debug', '--require-permission', 'android.permission.CAMERA')
            self.assertEqual(code, 1)
            code, text = self.run_main(path, '--debug', '--json')
            self.assertEqual(code, 0)
            report = json.loads(text)
            self.assertTrue(report['ok'])
            self.assertEqual(report['facts']['targetSdk'], 36)

    def test_says_so_when_the_debug_key_signed_the_apk(self):
        with tempfile.TemporaryDirectory() as folder:
            debug = Path(folder) / 'debug.apk'
            make_apk(debug, certificate=b'CN=Android Debug,O=Android,C=US',
                     libs={'lib/arm64-v8a/libgood.so': elf64(0x4000)})
            other = Path(folder) / 'other.apk'
            make_apk(other, certificate=b'CN=Someone Else',
                     libs={'lib/arm64-v8a/libgood.so': elf64(0x4000)})
            _, text = self.run_main(debug, '--debug')
            self.assertIn('NOTE signed with the Android debug key', text)
            self.assertIn('cannot update, or be updated by', text)
            _, text = self.run_main(other, '--debug')
            self.assertNotIn('NOTE', text)

    def test_a_missing_file_is_bad_input(self):
        saved, sys.stderr = sys.stderr, io.StringIO()
        try:
            self.assertEqual(verify_apk.main(['does-not-exist.apk']), 2)
        finally:
            sys.stderr = saved


if __name__ == '__main__':
    unittest.main()

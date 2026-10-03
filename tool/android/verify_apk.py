#!/usr/bin/env python3
"""Checks a built APK against the app's Android contract.

It needs only Python 3.9+ and the APK: no Android SDK, so it runs on the
learner's PC, in CI and on a build machine alike. It reads the binary
manifest, the native libraries and the signing block, and fails if:

* the manifest asks for a permission outside the allow-list. The app works
  offline (README), so a release APK must not hold INTERNET; ML Kit's
  libraries merge it in unless the release manifest removes it;
* the app targets an API level below the minimum, is debuggable, allows
  cleartext traffic, or lacks the backup rules that keep recovered scans out
  of backups;
* a 64-bit native library has a LOAD segment aligned below 16 KB, or sits in
  the APK at an offset that is not a multiple of 16 KB (Google Play, Android
  15+; tool/check_16kb_alignment.sh does the same with readelf and zipalign);
* the APK carries no v2 or later signature.

    python tool/android/verify_apk.py build/app/outputs/flutter-apk/app-release.apk
    python tool/android/verify_apk.py app-debug.apk --debug      # debug builds
    python tool/android/verify_apk.py app-debug.apk --debug         --require-permission android.permission.INTERNET          # the Flutter tool

Exit status: 0 when every check passes, 1 when one fails, 2 for bad input.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from dataclasses import dataclass, field

PACKAGE = 'com.xaiando.sommelier'
ANDROID_NS = 'http://schemas.android.com/apk/res/android'

# Permissions a release build may hold. The app-local one is AndroidX's guard
# for dynamically registered receivers. ACCESS_NETWORK_STATE only reports
# whether a network exists: it cannot send anything.
ALLOWED_PERMISSIONS = {
    'android.permission.ACCESS_NETWORK_STATE',
    f'{PACKAGE}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
}
# Debug and profile builds also need INTERNET for the Flutter tool.
DEBUG_PERMISSIONS = ALLOWED_PERMISSIONS | {'android.permission.INTERNET'}

MIN_TARGET_SDK = 35
LOAD_ALIGNMENT = 16 * 1024
# The Android debug keystore's certificate is issued to this name. A build
# machine makes the key afresh, so what it signs cannot update, or be updated
# by, an app signed with any other key.
DEBUG_KEY_NAME = b'Android Debug'
SIGNING_SCHEMES = {
    0x7109871A: 'v2',
    0xF05368C0: 'v3',
    0x1B93AD61: 'v3.1',
}


class ApkError(Exception):
    """The file is not an APK this tool can read."""


# --- Binary XML (AXML) -----------------------------------------------------

_RES_STRING_POOL = 0x0001
_RES_XML_START_ELEMENT = 0x0102
_RES_XML_END_ELEMENT = 0x0103

_TYPE_REFERENCE = 0x01
_TYPE_STRING = 0x03
_TYPE_INT_DEC = 0x10
_TYPE_INT_HEX = 0x11
_TYPE_BOOLEAN = 0x12


@dataclass
class Element:
    tag: str
    attributes: dict[str, object] = field(default_factory=dict)
    children: list['Element'] = field(default_factory=list)

    def find_all(self, tag: str):
        if self.tag == tag:
            yield self
        for child in self.children:
            yield from child.find_all(tag)

    def android(self, name: str, default=None):
        return self.attributes.get(f'{{{ANDROID_NS}}}{name}', default)


def _read_string_pool(data: bytes, start: int) -> list[str]:
    (_, header_size, size, count, _style_count, flags, strings_start,
     _styles_start) = struct.unpack_from('<HHIIIIII', data, start)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f'<{count}I', data, start + header_size)
    base = start + strings_start
    strings = []
    for offset in offsets:
        position = base + offset
        if utf8:
            # Two lengths: characters, then bytes; each is one or two bytes.
            first = data[position]
            position += 2 if first & 0x80 else 1
            length = data[position]
            position += 1
            if length & 0x80:
                length = ((length & 0x7F) << 8) | data[position]
                position += 1
            strings.append(data[position:position + length].decode('utf-8', 'replace'))
        else:
            length = struct.unpack_from('<H', data, position)[0]
            position += 2
            if length & 0x8000:
                length = ((length & 0x7FFF) << 16) | struct.unpack_from('<H', data, position)[0]
                position += 2
            strings.append(data[position:position + length * 2].decode('utf-16-le', 'replace'))
    return strings


def parse_manifest(data: bytes) -> Element:
    """Decodes a compiled AndroidManifest.xml into an element tree."""
    if len(data) < 8 or struct.unpack_from('<H', data, 0)[0] != 0x0003:
        raise ApkError('AndroidManifest.xml is not binary XML')
    strings: list[str] = []
    stack: list[Element] = []
    root: Element | None = None
    position = struct.unpack_from('<H', data, 2)[0]
    while position + 8 <= len(data):
        chunk_type, header_size, size = struct.unpack_from('<HHI', data, position)
        if size < 8:
            raise ApkError('corrupt binary XML chunk')
        if chunk_type == _RES_STRING_POOL:
            strings = _read_string_pool(data, position)
        elif chunk_type == _RES_XML_START_ELEMENT:
            body = position + header_size
            ns, name, _attr_start, attr_size, attr_count = struct.unpack_from('<iiHHH', data, body)
            element = Element(strings[name])
            attributes_at = body + 20
            for index in range(attr_count):
                a_ns, a_name, raw, _size, _res0, kind, value = struct.unpack_from(
                    '<iiiHBBI', data, attributes_at + index * attr_size)
                key = strings[a_name]
                if a_ns >= 0:
                    key = f'{{{strings[a_ns]}}}{key}'
                if raw >= 0:
                    parsed: object = strings[raw]
                elif kind == _TYPE_STRING:
                    parsed = strings[value]
                elif kind == _TYPE_BOOLEAN:
                    parsed = value != 0
                elif kind in (_TYPE_INT_DEC, _TYPE_INT_HEX):
                    parsed = struct.unpack('<i', struct.pack('<I', value))[0]
                elif kind == _TYPE_REFERENCE:
                    parsed = f'@0x{value:08x}'
                else:
                    parsed = value
                element.attributes[key] = parsed
            if stack:
                stack[-1].children.append(element)
            else:
                root = root or element
            stack.append(element)
        elif chunk_type == _RES_XML_END_ELEMENT:
            if stack:
                stack.pop()
        position += size
    if root is None:
        raise ApkError('AndroidManifest.xml has no root element')
    return root


# --- Checks ----------------------------------------------------------------


@dataclass
class Result:
    problems: list[str] = field(default_factory=list)
    facts: dict[str, object] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.problems


def check_manifest(manifest: Element, result: Result, *, debug: bool,
                   required: tuple[str, ...] = ()) -> None:
    permissions = sorted(
        str(node.android('name')) for node in manifest.find_all('uses-permission'))
    permissions += sorted(
        str(node.android('name')) for node in manifest.find_all('uses-permission-sdk-23'))
    sdk = next(manifest.find_all('uses-sdk'), None)
    application = next(manifest.find_all('application'), None)
    result.facts.update(
        package=manifest.attributes.get('package'),
        versionName=manifest.android('versionName'),
        versionCode=manifest.android('versionCode'),
        minSdk=sdk.android('minSdkVersion') if sdk else None,
        targetSdk=sdk.android('targetSdkVersion') if sdk else None,
        permissions=permissions,
    )
    if manifest.attributes.get('package') != PACKAGE:
        result.problems.append(
            f'package is {manifest.attributes.get("package")!r}, expected {PACKAGE!r}')

    allowed = DEBUG_PERMISSIONS if debug else ALLOWED_PERMISSIONS
    for name in required:
        if name not in permissions:
            result.problems.append(f'permission {name} is required but missing')
    for name in permissions:
        if name not in allowed:
            hint = ''
            if name == 'android.permission.INTERNET':
                hint = (' (ML Kit merges it in; src/release/AndroidManifest.xml '
                        'removes it for release builds)')
            result.problems.append(f'permission {name} is not allowed{hint}')

    if sdk is None or sdk.android('targetSdkVersion') is None:
        result.problems.append('no targetSdkVersion in the manifest')
    elif sdk.android('targetSdkVersion') < MIN_TARGET_SDK:
        result.problems.append(
            f'targetSdkVersion {sdk.android("targetSdkVersion")} is below {MIN_TARGET_SDK}')

    if application is None:
        result.problems.append('no <application> element')
        return
    if application.android('debuggable') is True and not debug:
        result.problems.append('the release build is debuggable')
    if application.android('usesCleartextTraffic') is True:
        result.problems.append('cleartext traffic is allowed')
    for rule in ('fullBackupContent', 'dataExtractionRules'):
        if application.android(rule) is None:
            result.problems.append(
                f'application has no {rule}: recovered scans would enter backups')
    result.facts['allowBackup'] = application.android('allowBackup')
    result.facts['extractNativeLibs'] = application.android('extractNativeLibs')


def elf_load_alignments(blob: bytes) -> list[int] | None:
    """The p_align of each PT_LOAD segment of a 64-bit little-endian ELF."""
    if len(blob) < 64 or blob[:4] != b'\x7fELF' or blob[4] != 2 or blob[5] != 1:
        return None
    e_phoff = struct.unpack_from('<Q', blob, 0x20)[0]
    e_phentsize, e_phnum = struct.unpack_from('<HH', blob, 0x36)
    alignments = []
    for index in range(e_phnum):
        offset = e_phoff + index * e_phentsize
        if struct.unpack_from('<I', blob, offset)[0] == 1:  # PT_LOAD
            alignments.append(struct.unpack_from('<Q', blob, offset + 0x30)[0])
    return alignments


def entry_data_offset(apk: bytes, info: zipfile.ZipInfo) -> int:
    name_length, extra_length = struct.unpack_from('<HH', apk, info.header_offset + 26)
    return info.header_offset + 30 + name_length + extra_length


def check_native_libraries(apk: bytes, archive: zipfile.ZipFile, result: Result) -> None:
    abis: dict[str, int] = {}
    checked = 0
    for info in archive.infolist():
        if not (info.filename.startswith('lib/') and info.filename.endswith('.so')):
            continue
        abi = info.filename.split('/')[1]
        abis[abi] = abis.get(abi, 0) + 1
        if abi not in ('arm64-v8a', 'x86_64'):
            continue  # Only 64-bit libraries are held to 16 KB.
        checked += 1
        alignments = elf_load_alignments(archive.read(info))
        if alignments is None:
            result.problems.append(f'{info.filename} is not a 64-bit ELF library')
        elif any(value < LOAD_ALIGNMENT for value in alignments):
            result.problems.append(
                f'{info.filename} has a LOAD segment aligned to {min(alignments)} '
                f'(needs {LOAD_ALIGNMENT})')
        if info.compress_type != zipfile.ZIP_STORED:
            result.problems.append(f'{info.filename} is compressed in the APK')
        elif entry_data_offset(apk, info) % LOAD_ALIGNMENT:
            result.problems.append(f'{info.filename} is not 16 KB-aligned in the APK')
    result.facts['abis'] = abis
    result.facts['libraries16kbChecked'] = checked


def read_signing_block(apk: bytes) -> tuple[list[str], list[bytes]]:
    """The signature schemes present, and the DER certificates that signed."""
    marker = b'APK Sig Block 42'
    position = apk.rfind(marker)
    if position < 8:
        return [], []
    block_size = struct.unpack_from('<Q', apk, position - 8)[0]
    start = position + len(marker) - block_size - 8
    cursor = start + 8
    schemes: list[str] = []
    certificates: list[bytes] = []
    while cursor < position - 8:
        pair_length = struct.unpack_from('<Q', apk, cursor)[0]
        pair_id = struct.unpack_from('<I', apk, cursor + 8)[0]
        value = apk[cursor + 12:cursor + 8 + pair_length]
        if pair_id in SIGNING_SCHEMES:
            schemes.append(SIGNING_SCHEMES[pair_id])
            certificates += _certificates(value)
        cursor += 8 + pair_length
    return schemes, certificates


def signing_schemes(apk: bytes) -> tuple[list[str], list[str]]:
    """The signature schemes present, and the SHA-256 of each signing certificate."""
    schemes, certificates = read_signing_block(apk)
    fingerprints = {hashlib.sha256(c).hexdigest().upper() for c in certificates}
    return schemes, sorted(fingerprints)


def _certificates(block: bytes) -> list[bytes]:
    """The DER certificates in a v2 or v3 signer block."""
    def length_prefixed(data: bytes, at: int) -> tuple[bytes, int]:
        size = struct.unpack_from('<I', data, at)[0]
        return data[at + 4:at + 4 + size], at + 4 + size

    out = []
    try:
        signers, _ = length_prefixed(block, 0)
        at = 0
        while at < len(signers):
            signer, at = length_prefixed(signers, at)
            signed_data, _ = length_prefixed(signer, 0)
            _digests, after = length_prefixed(signed_data, 0)
            certificates, _ = length_prefixed(signed_data, after)
            inner = 0
            while inner < len(certificates):
                certificate, inner = length_prefixed(certificates, inner)
                out.append(certificate)
    except (struct.error, IndexError):
        pass
    return out


def check_signing(apk: bytes, archive: zipfile.ZipFile, result: Result) -> None:
    schemes, certificates = read_signing_block(apk)
    fingerprints = sorted({hashlib.sha256(c).hexdigest().upper() for c in certificates})
    legacy = [n for n in archive.namelist()
              if n.startswith('META-INF/') and n.endswith(('.RSA', '.DSA', '.EC'))]
    result.facts['signatureSchemes'] = schemes + (['v1'] if legacy else [])
    result.facts['certificateSha256'] = fingerprints
    result.facts['signedWithDebugKey'] = any(DEBUG_KEY_NAME in c for c in certificates)
    if not schemes:
        result.problems.append('the APK has no v2 or later signature')


def verify(path: str, *, debug: bool = False,
           required: tuple[str, ...] = ()) -> Result:
    try:
        with open(path, 'rb') as handle:
            apk = handle.read()
        archive = zipfile.ZipFile(path)
        manifest_bytes = archive.read('AndroidManifest.xml')
    except (OSError, zipfile.BadZipFile, KeyError) as error:
        raise ApkError(f'{path}: {error}') from error
    result = Result()
    result.facts['file'] = path
    result.facts['bytes'] = len(apk)
    result.facts['sha256'] = hashlib.sha256(apk).hexdigest().upper()
    check_manifest(parse_manifest(manifest_bytes), result, debug=debug,
                   required=required)
    check_native_libraries(apk, archive, result)
    check_signing(apk, archive, result)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('apk')
    parser.add_argument('--debug', action='store_true',
                        help='a debug or profile build: INTERNET is allowed')
    parser.add_argument('--require-permission', action='append', default=[],
                        metavar='NAME',
                        help='fail unless the manifest holds this permission '
                             '(a debug APK needs android.permission.INTERNET)')
    parser.add_argument('--json', action='store_true', help='print the result as JSON')
    options = parser.parse_args(argv)
    try:
        result = verify(options.apk, debug=options.debug,
                        required=tuple(options.require_permission))
    except ApkError as error:
        print(f'error: {error}', file=sys.stderr)
        return 2
    if options.json:
        print(json.dumps({'ok': result.ok, 'problems': result.problems,
                          'facts': result.facts}, indent=2))
    else:
        for key, value in result.facts.items():
            print(f'{key:22} {value}')
        print()
        for problem in result.problems:
            print(f'FAIL {problem}')
        if result.facts.get('signedWithDebugKey'):
            print('NOTE signed with the Android debug key, which a build machine makes afresh: '
                  'this APK cannot update, or be updated by, an app installed from a build '
                  'signed with any other key (docs/android-acceptance.md, "Updating").')
        print('OK: every check passed.' if result.ok
              else f'{len(result.problems)} check(s) failed.')
    return 0 if result.ok else 1


if __name__ == '__main__':
    sys.exit(main())

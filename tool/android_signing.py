#!/usr/bin/env python3
"""Prepare signing without printing credentials; PR builds are always unsigned."""
import base64
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS')


def property_value(value):
    # java.util.Properties escapes; do not let a newline inject another property.
    escaped = (value.replace('\\', '\\\\').replace('\n', '\\n')
            .replace('\r', '\\r').replace('\t', '\\t')
            .replace(' ', '\\ ').replace('=', '\\=').replace(':', '\\:'))
    result = []
    for character in escaped:
        if ord(character) < 128:
            result.append(character)
        else:
            encoded = character.encode('utf-16-be')
            for offset in range(0, len(encoded), 2):
                result.append(f'\\u{int.from_bytes(encoded[offset:offset + 2], "big"):04x}')
    return ''.join(result)


def prepare(root, environment):
    properties = root / 'simple_live_app/android/key.properties'
    status = root / 'simple_live_app/build/signing-status/SIGNING_STATUS.txt'
    status.parent.mkdir(parents=True, exist_ok=True)
    if environment.get('BUILD_EVENT') == 'pull_request':
        properties.unlink(missing_ok=True)
        status.write_text('UNSIGNED PR BUILD: validation only; not an installable signed release.\n')
        return 'unsigned'
    missing = [key for key in KEYS if not environment.get(key)]
    if missing:
        raise ValueError('Missing required Android signing secrets: ' + ', '.join(missing))
    try:
        keystore = base64.b64decode(''.join(environment['KEYSTORE_BASE64'].split()), validate=True)
    except (ValueError, base64.binascii.Error):
        raise ValueError('KEYSTORE_BASE64 must be valid base64') from None
    if not keystore:
        raise ValueError('Android keystore is empty')
    keystore_path = root / 'simple_live_app/android/ci-keystore.jks'
    keystore_path.write_bytes(keystore)
    keystore_path.chmod(0o600)
    values = {'storeFile': keystore_path.as_posix(),
              'storePassword': environment['STORE_PASSWORD'],
              'keyPassword': environment['KEY_PASSWORD'],
              'keyAlias': environment['KEY_ALIAS']}
    properties.write_text(''.join(f'{key}={property_value(value)}\n' for key, value in values.items()), encoding='utf-8')
    properties.chmod(0o600)
    status.write_text('SIGNED BUILD: configured with this fork\'s Android signing identity.\n')
    return 'signed'


if __name__ == '__main__':
    try:
        print('Android signing: ' + prepare(ROOT, os.environ))
    except (ValueError, OSError) as error:
        print(f'Android signing failed: {error}', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Synchronize and validate the Flutter app's package/release version."""
import argparse
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / 'simple_live_app/pubspec.yaml'
MANIFEST = ROOT / 'assets/app_version.json'
DOWNLOAD_URL = 'https://github.com/cyocyo10/dart_simple_live/releases'
VERSION = re.compile(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)')


def parse_version(value):
    match = VERSION.fullmatch(value)
    if not match:
        raise ValueError('Use MAJOR.MINOR.PATCH+BUILD, for example 1.14.0+11400')
    numbers = tuple(map(int, match.groups()))
    if any(number > 65535 for number in numbers):
        raise ValueError('Version components must fit Windows version fields (0..65535)')
    return numbers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--set', metavar='VERSION', help='Bump pubspec and JSON together; update CHANGELOG separately')
    parser.add_argument('--tag', help='Validate a vX.Y.Z or dev_vX.Y.Z tag (defaults to GITHUB_REF on tag builds)')
    args = parser.parse_args()
    source = PUBSPEC.read_text(encoding='utf-8')
    found = re.search(r'^version:\s*(\S+)\s*$', source, re.MULTILINE)
    if not found:
        raise ValueError('Missing app pubspec version')
    current = found.group(1)
    current_numbers = parse_version(current)
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    if args.set:
        numbers = parse_version(args.set)
        if numbers[:3] < current_numbers[:3] or numbers[3] <= current_numbers[3]:
            raise ValueError('Version must not decrease and BUILD must increase')
        current = args.set
        source = source[:found.start(1)] + current + source[found.end(1):]
        manifest.update(version=current.split('+')[0], version_num=numbers[3], download_url=DOWNLOAD_URL)
    numbers = parse_version(current)
    name = current.split('+')[0]
    if manifest.get('version') != name or manifest.get('version_num') != numbers[3]:
        raise ValueError('assets/app_version.json does not match the app pubspec version')
    if manifest.get('download_url') != DOWNLOAD_URL:
        raise ValueError('App download URL must point to this fork')
    tag = args.tag
    ref = os.environ.get('GITHUB_REF', '')
    if tag is None and ref.startswith('refs/tags/'):
        tag = ref.removeprefix('refs/tags/')
    if tag is not None and tag not in (f'v{name}', f'dev_v{name}'):
        raise ValueError(f'Tag {tag!r} does not match app version {name}; expected v{name} or dev_v{name}')
    if args.set:
        # Validate the manifest and tag before changing either tracked file.
        PUBSPEC.write_text(source, encoding='utf-8')
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')
    print(f'App version: {current}' + (f' (tag {tag})' if tag else ''))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(f'Version check failed: {error}', file=sys.stderr)
        sys.exit(1)

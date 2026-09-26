#!/usr/bin/env python3
"""Collect the three build artifacts and generate verifiable release metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def collect(artifacts, output, metadata):
    groups = {'android-apk': ('*.apk', 3), 'windows-portable': ('*.zip', 1),
              'windows-msix': ('*.msix', 1)}
    files = []
    for name, (pattern, count) in groups.items():
        found = list((artifacts / name).rglob(pattern))
        if len(found) != count:
            raise ValueError(f'{name}: expected {count} {pattern} files, found {len(found)}')
        files.extend(found)
    status = artifacts / 'android-apk/SIGNING_STATUS.txt'
    if not status.is_file() or not status.read_text().startswith('SIGNED BUILD:'):
        raise ValueError('Release APKs must come from a signed build')
    if any('unsigned' in path.name or path.stat().st_size == 0 for path in files):
        raise ValueError('Release assets cannot be unsigned or empty')
    if len({path.name for path in files}) != len(files):
        raise ValueError('Release asset names must be unique')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Release output directory must be empty')
    output.mkdir(parents=True, exist_ok=True)
    for path in files:
        shutil.copyfile(path, output / path.name)
    (output / 'BUILD_INFO.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    checksums = []
    for path in sorted(output.iterdir()):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        checksums.append(f'{digest}  {path.name}\n')
    (output / 'SHA256SUMS').write_text(''.join(checksums), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    for field in ('repository', 'sha', 'version', 'channel', 'tag', 'run-url'):
        parser.add_argument('--' + field, required=True)
    args = parser.parse_args()
    collect(args.artifacts, args.output, {field: getattr(args, field.replace('-', '_'))
            for field in ('repository', 'sha', 'version', 'channel', 'tag', 'run-url')})

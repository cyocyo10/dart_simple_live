#!/usr/bin/env python3
"""Check fork identity, app version, and channel ancestry before release builds."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

from app_version import ROOT, parse_version

REPOSITORY = 'cyocyo10/dart_simple_live'


def git(root, *arguments):
    return subprocess.run(['git', '-C', str(root), *arguments], check=True,
                          text=True, capture_output=True).stdout.strip()


def validate(repository, tag, version, commit, root=ROOT):
    if repository != REPOSITORY:
        raise ValueError(f'Release workflow is maintained only for {REPOSITORY}')
    parse_version(version)
    name = version.split('+')[0]
    if tag == f'v{name}':
        branch, channel = 'master', 'stable'
    elif tag == f'dev_v{name}':
        branch, channel = 'dev', 'dev'
    else:
        raise ValueError('Tag must exactly match vVERSION or dev_vVERSION')
    if not re.fullmatch(r'[0-9a-fA-F]{40}', commit):
        raise ValueError('Commit must be a full SHA')
    head = git(root, 'rev-parse', 'HEAD^{commit}')
    tagged = git(root, 'rev-parse', f'refs/tags/{tag}^{{commit}}')
    if commit.lower() != head or tagged != head:
        raise ValueError('Checkout, event SHA, and tag must identify the same commit')
    result = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor',
                             head, f'refs/remotes/origin/{branch}'], capture_output=True)
    if result.returncode != 0:
        raise ValueError(f'Tagged commit must already belong to origin/{branch}')
    return channel


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY', ''))
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME', ''))
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA', ''))
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / 'tool/app_version.py'), '--tag', args.tag], check=True)
    source = (ROOT / 'simple_live_app/pubspec.yaml').read_text(encoding='utf-8')
    version = re.search(r'^version:\s*(\S+)\s*$', source, re.MULTILINE).group(1)
    channel = validate(args.repository, args.tag, version, args.commit)
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a', encoding='utf-8') as stream:
            stream.write(f'channel={channel}\nversion={version}\ntag={args.tag}\n')
    print(f'Release policy passed: {channel} {version} {args.commit}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Release policy failed: {error}', file=sys.stderr)
        sys.exit(1)

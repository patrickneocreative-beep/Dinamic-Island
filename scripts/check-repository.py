#!/usr/bin/env python3
"""Check publishable files. No network access and no reading of user preferences."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import unquote

root = Path(__file__).resolve().parents[1]
if (root / '.git').exists():
    result = subprocess.run(['git', 'ls-files', '--cached', '-z'], cwd=root, check=True, capture_output=True)
    files = [root / p.decode() for p in result.stdout.split(b'\0') if p]
else:
    ignored = {'.git', 'build', 'dist', '.build', '__pycache__'}
    files = [p for p in root.rglob('*') if p.is_file() and not ignored.intersection(p.relative_to(root).parts)]
errors = []
required = ['README.md', 'LICENSE', 'PRIVACY.md', 'CONTRIBUTING.md', 'SECURITY.md',
            'CHANGELOG.md', 'Info.plist', 'build.sh', '.gitignore', '.github/workflows/ci.yml',
            'scripts/package.sh', 'docs/INSTALL.md', 'docs/TESTING.md', 'Resources/AppIcon.icns']
for name in required:
    if not (root / name).is_file():
        errors.append(f'Missing required file: {name}')
if not files:
    errors.append('No publishable files; stage the intended source files first.')
private_path = re.compile('/' + 'Users' + r'/[^/\s]+/')
patterns = [
    re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}'),
    re.compile(r'github_pat_[A-Za-z0-9_]{40,}'),
    re.compile(r'AKIA[0-9A-Z]{16}'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
]
for path in files:
    rel = path.relative_to(root)
    if not path.is_file():
        errors.append(f'Missing staged file: {rel}')
        continue
    if path.is_symlink():
        errors.append(f'Symlink needs review: {rel}')
        continue
    if {'build', 'dist', '.build', '__pycache__'}.intersection(rel.parts) or any(p.endswith('.app') for p in rel.parts):
        errors.append(f'Generated file staged: {rel}')
    if path.name.startswith('.env') or path.name in {'.DS_Store', 'clipboard-pins.json'} or path.suffix in {'.key', '.pem', '.p12', '.p8', '.log', '.jsonl', '.zip', '.dmg'}:
        errors.append(f'Local or sensitive file staged: {rel}')
    if path.stat().st_size > 2_000_000:
        errors.append(f'Unexpected large source asset: {rel}')
    if path.suffix in {'.png', '.icns'}:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        errors.append(f'Unexpected binary: {rel}')
        continue
    if private_path.search(text):
        errors.append(f'Absolute user path found: {rel}')
    for pattern in patterns:
        if pattern.search(text):
            errors.append(f'Credential-like content needs review: {rel}')
            break
    if path.suffix == '.md':
        for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text):
            target = target.split(' "', 1)[0].strip('<>')
            if '://' in target or target.startswith(('#', 'mailto:')):
                continue
            destination = (path.parent / unquote(target.split('#', 1)[0])).resolve()
            if not destination.is_relative_to(root) or not destination.exists():
                errors.append(f'Broken local link in {rel}: {target}')
info = plistlib.loads((root / 'Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    errors.append('Invalid release version')
if not (root / 'docs/releases' / f'v{version}.md').is_file():
    errors.append('Missing release notes for Info.plist version')
if info.get('CFBundleIdentifier') != 'local.isla.prototype':
    errors.append('Bundle identifier changed; review migration before releasing')
license_text = (root / 'LICENSE').read_text()
if not license_text.startswith('MIT License\n') or 'Copyright (c) 2026 Patrick Flores' not in license_text:
    errors.append('Expected MIT license and attribution missing')
if errors:
    for error in errors:
        print('FAIL:', error)
    sys.exit(1)
print(f'PASS: {len(files)} publishable files; structure, local links, version {version}, MIT license and credential/path checks.')

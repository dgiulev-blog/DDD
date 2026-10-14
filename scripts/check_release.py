"""Structural release checks. Does not launch DDD or touch user preferences."""
import hashlib
import plistlib
import re
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
app = root / 'build/DDD.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'io.prim.ddd'
assert info['CFBundleShortVersionString'] == version
assert info['LSMinimumSystemVersion'] == '14.0'
assert info['LSUIElement'] is True
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
archs = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/DDD')], text=True).split()
assert set(archs) <= {'arm64', 'x86_64'} and archs
print('PASS bundle metadata, code signature, architectures:', ', '.join(archs))

# Fail on obvious secrets and local/private path leaks in published text sources.
patterns = [r'gh[pousr]_[A-Za-z0-9]{20,}', r'sk-[A-Za-z0-9]{20,}',
            r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', r'/Users/dg/',
            r'100\.(?:[6-9][0-9]|1[01][0-9]|12[0-7])\.\d+\.\d+']
for folder in ['Sources', 'docs', 'scripts', '.github']:
    for p in (root / folder).rglob('*'):
        if p.suffix not in {'.swift', '.md', '.py', '.sh', '.yml'}:
            continue
        # Scanner intentionally contains its own search expressions.
        if p.resolve() == Path(__file__).resolve():
            continue
        text = p.read_text()
        for pattern in patterns:
            assert not re.search(pattern, text), f'Potential private value in {p.relative_to(root)}'
print('PASS public-source secret/local-path scan (heuristic, not a security audit)')

archive = root / f'dist/DDD-{version}-macos-universal.zip'
if archive.exists():
    assert set(archs) == {'arm64', 'x86_64'}, 'Universal archive requires both slices'
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        assert all(n.startswith(('DDD.app/', '__MACOSX/')) for n in names)
        assert not any(n.lower().endswith(('.json', '.xlsx', '.png', '.jsonl')) for n in names)
        packed = z.read('DDD.app/Contents/MacOS/DDD')
        assert packed == (app / 'Contents/MacOS/DDD').read_bytes()
    checksum_line = (root / 'dist/SHA256SUMS.txt').read_text().strip()
    digest, filename = checksum_line.split(maxsplit=1)
    assert filename == archive.name
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
    print('PASS universal ZIP allowlist, binary equality, SHA-256')

# Resolve local Markdown links without requiring external network access.
for p in [root / 'README.md', *root.glob('docs/*.md'), root / 'CONTRIBUTING.md']:
    if not p.exists():
        continue
    for target in re.findall(r'\]\(([^)]+)\)', p.read_text()):
        if '://' in target or target.startswith(('#', 'mailto:')):
            continue
        path = target.split('#', 1)[0]
        assert (p.parent / path).exists(), f'Broken link: {p.name}: {target}'
print('PASS local documentation links')

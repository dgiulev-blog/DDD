"""Generate the distributable bundle metadata, without local paths or settings."""
import plistlib
import re
import sys
from pathlib import Path

version, output = sys.argv[1:]
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("VERSION must be three numeric components")
info = {
    "CFBundleName": "DDD",
    "CFBundleDisplayName": "DDD",
    "CFBundleIdentifier": "io.prim.ddd",
    "CFBundleExecutable": "DDD",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "LSMinimumSystemVersion": "14.0",
    "LSUIElement": True,
    "NSHighResolutionCapable": True,
}
Path(output).write_bytes(plistlib.dumps(info))

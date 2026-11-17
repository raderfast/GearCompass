"""Build the installable GearCompass ZIP from the files listed in the TOC.

Usage:
    python scripts/build.py              # writes dist/GearCompass-<version>.zip
    python scripts/build.py --tag v1.2.3 # also fails unless the tag matches the TOC version

Prints the path of the archive. Used both locally and by the release workflow.
"""
import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = 'GearCompass'
EXTRA = ['LICENSE', 'README.md']


def read_toc():
    toc = ROOT / f'{ADDON}.toc'
    version, files = None, []
    for line in toc.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        match = re.match(r'^##\s*Version:\s*(\S+)', line)
        if match:
            version = match.group(1)
        elif line and not line.startswith('#'):
            files.append(line.replace('\\', '/'))
    if not version:
        sys.exit(f'{toc.name}: no "## Version:" line')
    return version, files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--tag', help='release tag that must equal "v" + TOC version')
    parser.add_argument('--out', default=str(ROOT / 'dist'), help='output directory')
    args = parser.parse_args()

    version, files = read_toc()
    if args.tag and args.tag != f'v{version}':
        sys.exit(f'Tag {args.tag} does not match TOC version {version} (expected v{version})')

    entries = [f'{ADDON}.toc'] + files + EXTRA
    missing = [name for name in entries if not (ROOT / name).is_file()]
    if missing:
        sys.exit('Missing files: ' + ', '.join(missing))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    archive = out / f'{ADDON}-{version}.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in entries:
            # Fixed timestamp: the same sources give the same archive.
            info = zipfile.ZipInfo(f'{ADDON}/{name}', date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, (ROOT / name).read_bytes())
    print(archive)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Validate the live-only starter snapshots and build the OwnTV playlist."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'assets/catalog'


def render():
    manifest = json.loads((CATALOG / 'manifest.json').read_text())
    if not re.fullmatch(r'[A-Za-z0-9.-]+', manifest['revision']):
        raise ValueError('Invalid catalog revision')
    guides = []
    entries = []
    seen = set()
    for source in manifest['sources']:
        content = (CATALOG / source['file']).read_bytes()
        if sha256(content).hexdigest() != source['sha256']:
            raise ValueError(f"Checksum mismatch: {source['file']}")
        lines = content.decode().splitlines()
        if not lines or not lines[0].startswith('#EXTM3U'):
            raise ValueError(f"Missing M3U header: {source['file']}")
        guides.append(source['epgUrl'])
        pending = None
        count = 0
        for line in lines[1:]:
            if line.startswith('#EXTINF:'):
                if pending is not None:
                    raise ValueError('Channel metadata has no stream')
                if re.search(r'(?:type|media-type)="(?:movie|series)"', line, re.I):
                    raise ValueError('Starter playlists must contain live TV only')
                pending = line
            elif line and not line.startswith('#'):
                if pending is None or not line.startswith(('https://', 'http://')):
                    raise ValueError('Invalid channel stream')
                if not re.search(r'\.m3u8(?:[?#]|$)', line, re.I):
                    raise ValueError('Only live HLS streams belong in the starter')
                if line not in seen:
                    # OwnTV displays semicolon-separated categories literally.
                    metadata = pending.replace('group-title="Sports;Sports | ',
                                               'group-title="Sports | ')
                    entries.extend([metadata, line])
                    seen.add(line)
                pending = None
                count += 1
        if pending is not None or not count:
            raise ValueError('Incomplete or empty live catalog')
    header = '#EXTM3U url-tvg="' + ','.join(dict.fromkeys(guides)) + '"'
    return '\n'.join([header, *entries]) + '\n', len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify without writing')
    args = parser.parse_args()
    content, count = render()
    destination = ROOT / 'playlists/owntv.m3u'
    if args.check:
        if not destination.is_file() or destination.read_text() != content:
            sys.exit('Run python3 scripts/catalog.py to update playlists/owntv.m3u')
    else:
        destination.parent.mkdir(exist_ok=True)
        destination.write_text(content)
    print(f'Validated {count} public live streams; no on-demand catalog is bundled.')


if __name__ == '__main__':
    main()

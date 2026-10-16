#!/usr/bin/env python3
"""Build a signed Fire TV APK without writing signing passwords to disk."""
import os
from pathlib import Path
import shutil
import subprocess
import sys


root = Path(__file__).resolve().parents[1]
environment = os.environ.copy()
if sys.platform == 'darwin' and not environment.get('FIRE_IPTV_KEYSTORE'):
    key = Path.home() / 'Library/Application Support/FireTV/signing/fire-iptv/release.jks'
    if key.is_file():
        password = subprocess.check_output([
            '/usr/bin/security', 'find-generic-password',
            '-s', 'fire-iptv.release.password', '-w',
        ], text=True).strip()
        environment.update(FIRE_IPTV_KEYSTORE=str(key), FIRE_IPTV_KEY_ALIAS='fire-iptv',
                           FIRE_IPTV_STORE_PASSWORD=password, FIRE_IPTV_KEY_PASSWORD=password)

required = ['FIRE_IPTV_KEYSTORE', 'FIRE_IPTV_KEY_ALIAS',
            'FIRE_IPTV_STORE_PASSWORD', 'FIRE_IPTV_KEY_PASSWORD']
if any(not environment.get(name) for name in required):
    sys.exit('Set the FIRE_IPTV signing environment variables before building a release.')
if not Path(environment['FIRE_IPTV_KEYSTORE']).is_file():
    sys.exit('The release keystore could not be found.')

flutter = environment.get('FLUTTER_BIN') or shutil.which('flutter')
if not flutter:
    sys.exit('Install Flutter or set FLUTTER_BIN to its executable.')
subprocess.run([flutter, 'build', 'apk', '--release', '--target-platform',
                'android-arm,android-arm64'], cwd=root, env=environment, check=True)
destination = root / 'dist'
destination.mkdir(exist_ok=True)
shutil.copy2(root / 'build/app/outputs/flutter-apk/app-release.apk',
             destination / 'fire-iptv.apk')
print('Signed APK: dist/fire-iptv.apk')

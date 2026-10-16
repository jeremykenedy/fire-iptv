# Development and release builds

fire-iptv is a Fire TV fork of OpenIPTV v0.14.8
([22e3a5c](https://github.com/Hunter-Clipper/OpenIPTV/tree/22e3a5c3ef49a872390546feae9f039eb123eb96)).
The upstream player, database, profiles, provider parsers and parental controls
remain the foundation. Native Android code retains its upstream namespace;
the installable application ID is `com.jeremykenedy.fireiptv`.

## Toolchain

| Tool | Version |
| --- | --- |
| Flutter | 3.47.7 stable |
| Java | 17 or Android Studio JBR 21 |
| Android compile SDK | 36 |
| Android minimum | API 24, Android 7 |
| Android NDK | 28.2.13676358 |
| CMake | 3.22.1 |
| Gradle / Android Gradle Plugin | 8.14.3 / 8.11.1 |
| Kotlin | 2.2.20 |

```bash
git clone https://github.com/jeremykenedy/fire-iptv.git
cd fire-iptv
flutter pub get
flutter run -d <device-id>
```

The checked-in generated Drift and Riverpod code is sufficient for an ordinary
build. After changing annotated database/provider declarations, regenerate it:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The Gradle build fetches the pinned OpenVPN native sources through
`android/openvpn-deps.sh`. The first build needs network access and takes
longer than later builds. See [native dependency licenses](THIRD_PARTY_NATIVE.md).

## Checks

```bash
python3 scripts/catalog.py --check
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

CI performs these checks on Ubuntu. A contributor build without a configured
release key uses a debug signature. Do not distribute it as an official update.
The release APK includes 32-bit and 64-bit ARM; physical validation is currently
on a 32-bit Fire TV. Other inherited targets are not part of this release's
support claim.

Native verification should cover first launch, guide data, sports filtering,
search, provider setup, playback, Back/Menu/Home and an update that preserves
profiles, sources and favorites. Never replace actual TV navigation tests with
a direct activity launch alone.

## Signing

Use one stable private key for all official releases. Keep it outside the
repository. Supply these environment variables to `scripts/build-release.py`:

| Variable | Value |
| --- | --- |
| `FIRE_IPTV_KEYSTORE` | Absolute path to the release keystore |
| `FIRE_IPTV_KEY_ALIAS` | Keystore alias |
| `FIRE_IPTV_STORE_PASSWORD` | Password supplied by secure storage |
| `FIRE_IPTV_KEY_PASSWORD` | Key password supplied by secure storage |
| `FLUTTER_BIN` | Optional absolute Flutter executable path |

```bash
python3 scripts/build-release.py
```

The script refuses a release without signing credentials and writes
`dist/fire-iptv.apk`. On the maintainer's Mac it can read the existing private
keystore and its password from macOS Keychain. Passwords are passed only in the
build process environment. Do not write them into a properties file, shell
history or CI log.

Published release certificate SHA-256:

```text
5bfdd656c79da4291a15f2d80e4e4208aa027f563d7d9afb2cfe63469a147095
```

Publish from the verified remote `main` tip with a matching semantic version
tag. Verify the APK signature and package ID, attach the APK and checksum file,
and update the toolkit's pinned version and checksum in the same rollout.

## Architecture

- Flutter and Riverpod render the discovery, guide, search and provider UI.
- Drift stores the catalog in a SQLCipher database; credentials use Android
  secure storage through the inherited OpenIPTV storage layer.
- AndroidX Media3 ExoPlayer plays video through the native Flutter bridge.
- The starter service installs verified assets in one database transaction.
- Managed refreshes validate the downloaded live catalog before replacing
  cached data. A failed refresh keeps the previous catalog.
- Tubi and Plex launch through a fixed native package whitelist.

The project has no analytics or application account. It contacts configured
stream, image and guide hosts, this GitHub repository for catalog/app updates,
and the services requested through inherited network tools. Stream providers
and external applications have their own behavior.

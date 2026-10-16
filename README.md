<p align="center">
  <a href="https://github.com/jeremykenedy/fire-iptv#gh-light-mode-only"><picture><source media="(max-width: 600px) and (prefers-reduced-motion: reduce)" srcset="art/banner-mobile-still-light.4bd62666c0ff.svg"><source media="(prefers-reduced-motion: reduce)" srcset="art/banner-still-light.cf5ba343cd41.svg"><source media="(max-width: 600px)" srcset="art/banner-mobile-light.fd9c0e2fe84c.svg"><img src="art/banner-light.841172d6c0f7.svg#gh-light-mode-only" alt="fire-iptv" width="800"></picture></a>
  <a href="https://github.com/jeremykenedy/fire-iptv#gh-dark-mode-only"><picture><source media="(max-width: 600px) and (prefers-reduced-motion: reduce)" srcset="art/banner-mobile-still-dark.b4e6e2263d97.svg"><source media="(prefers-reduced-motion: reduce)" srcset="art/banner-still-dark.01f164475fb5.svg"><source media="(max-width: 600px)" srcset="art/banner-mobile-dark.e62aab811c28.svg"><img src="art/banner-dark.6348925e1da3.svg#gh-dark-mode-only" alt="fire-iptv" width="800"></picture></a>
</p>

<p align="center">A Fire TV guide and discovery app with automatic live TV setup, sports browsing, and your own movie and series libraries.</p>

<p align="center">
  <a href="https://github.com/jeremykenedy/fire-iptv/releases"><img src="https://img.shields.io/github/downloads/jeremykenedy/fire-iptv/total" alt="Total downloads"></a>
  <a href="https://github.com/jeremykenedy/fire-iptv/releases/latest"><img src="https://img.shields.io/github/v/release/jeremykenedy/fire-iptv" alt="Latest stable version"></a>
  <a href="https://github.com/jeremykenedy/fire-iptv/actions/workflows/tests.yml"><img src="https://github.com/jeremykenedy/fire-iptv/actions/workflows/tests.yml/badge.svg?branch=main" alt="Tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0 license"></a>
</p>

<p align="center">
  <a href="https://github.com/jeremykenedy"><img src="https://img.shields.io/github/followers/jeremykenedy?label=Follow%20me&amp;style=social" alt="Follow Jeremy Kenedy on GitHub"></a>
  <a href="https://github.com/jeremykenedy/fire-iptv/stargazers"><img src="https://img.shields.io/badge/Star-this%20repo-blue?logo=github" alt="Star this repository"></a>
  <a href="https://github.com/jeremykenedy/fire-iptv/stargazers"><img src="https://img.shields.io/github/stars/jeremykenedy/fire-iptv?style=social" alt="GitHub stars"></a>
  <a href="https://github.com/sponsors/jeremykenedy"><img src="https://img.shields.io/badge/Sponsor-jeremykenedy-ea4aaa?logo=githubsponsors&amp;logoColor=white" alt="Sponsor Jeremy Kenedy"></a>
</p>

## Table of Contents

- [Platform Support](#platform-support)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Features](#features)
- [Integrations](#integrations)
- [Configuration](#configuration)
- [Updating and Removing](#updating-and-removing)
- [Commands](#commands)
- [Testing](#testing)
- [File Tree](#file-tree)
- [Documentation](#documentation)
- [Screenshots](#screenshots)
- [Upstream](#upstream)
- [Changelog](#changelog)
- [License](#license)

## Platform Support

| Platform | Requirements | Verification |
| --- | --- | --- |
| Fire TV | Android 7 / API 24 or newer; 32-bit or 64-bit ARM | Guide, sports, search, provider setup, playback and updates tested on a physical 32-bit Fire TV running API 30 |
| Android TV and Google TV | Android 7 / API 24 or newer; 32-bit or 64-bit ARM | Android APK compiled for both ARM targets; physical devices beyond the tested Fire TV remain unverified |

The published APK targets Android TVs. The separate [Fire TV Toolkit desktop app](https://github.com/jeremykenedy/fire-tv-toolkit/blob/main/docs/DESKTOP.md) runs on macOS, Windows and Linux to manage a connected TV.

## Requirements

- Fire TV or Android TV running Android 7 / API 24 or newer, with a 32-bit or 64-bit ARM processor.
- Network access for streams, images and guide data.
- For the toolkit installer: macOS or Linux, Node.js 18+, and an authorized ADB connection to the TV.
- A provider with on-demand content to populate Movies and Series.

For a source build, use Flutter 3.47.7, Android compile SDK 36, and Java 17 or Android Studio JBR 21. The [development guide](docs/development.md#toolchain) lists the NDK, CMake and Gradle versions.

APK downloads include the application dependencies. Source contributors can find the [runtime package reference](docs/development.md#runtime-packages) in the development guide.

## Installation

1. Install [fire-tv-toolkit](https://github.com/jeremykenedy/fire-tv-toolkit#installation) and complete its initial setup.
2. Enable ADB debugging on the TV and authorize the toolkit's connection.
3. Install or update the player:

```bash
fire-iptv --install
```

The toolkit verifies the pinned APK checksum, preserves an existing installation's data, and opens the app. Its shared player menu also supports both players:

```bash
firetv-iptv
firetv-iptv --app=fire-iptv --install
firetv-iptv --app=owntv --install
```

For manual installation, download [fire-iptv.apk](https://github.com/jeremykenedy/fire-iptv/releases/latest/download/fire-iptv.apk) and `SHA256SUMS` from [Releases](https://github.com/jeremykenedy/fire-iptv/releases/latest). Verify the APK against its published checksum, then install it on the TV:

```bash
adb connect <tv-ip>:5555
adb -s <tv-ip>:5555 install -r fire-iptv.apk
```

## Quick Start

1. Open fire-iptv. The bundled live catalog and Everyone profile are prepared automatically.
2. Choose **TV guide** for the channel timeline or **All sports** to filter sports channels. Guide data loads in the background.
3. Select a channel to preview it; select again for full-screen playback. Back returns to the guide.
4. Open **Add provider** to add an M3U playlist/file or Xtream Codes login for your own movies and series.
5. Use **Search**, genre rows, favorites and Continue Watching to find titles from that library.

The starter includes 1,323 public live-channel links, including 226 sports channels in its October 16, 2026 snapshot. Availability varies by channel and region. It includes no on-demand movie or series collection. Tubi and Plex shortcuts open those separate applications and their own catalogs.

## Features

| Feature | Description |
| --- | --- |
| Automatic live TV setup | Prepares the public live-channel starter and Everyone profile on first launch |
| Discover | TV guide, sports and provider setup tiles with visible remote focus |
| TV guide | Channel logos, categories, now/next programs, a timeline and live preview |
| Sports guide | Filters available football, baseball, basketball, racing, combat sports and other sports channels |
| Provider libraries | Imports M3U playlists/files or Xtream Codes sources supplied by the owner |
| Movies and series | Provider posters, genres, title details, seasons and episodes |
| Discovery actions | Recent releases from supplied release years, recommendations and a random movie action |
| Search | Finds available live channels, movies, series and guide programs |
| Favorites and progress | Saved favorites and Continue Watching for the active profile |
| Household profiles | Multiple sources, profiles and inherited parental controls |
| Local data | Encrypted credential storage and backup/restore |
| Catalog recovery | Bundled starter installation and refresh recovery that keeps the last working catalog |
| Application shortcuts | Opens installed Tubi and Plex applications for administrator profiles on TV |
| Toolkit installation | Checksum-verified installation and updates that preserve existing application data |

A public live-channel directory cannot supply every film, series, subscription network or premium sports event. [Catalog and provider documentation](docs/catalog.md) explains how the pieces fit together.

## Integrations

| Integration | How it is used |
| --- | --- |
| [Fire TV Toolkit](https://github.com/jeremykenedy/fire-tv-toolkit) | Installs, updates, opens or removes the player over an authorized ADB connection |
| [iptv-org](https://github.com/iptv-org/iptv) | Public live-channel sources used to prepare the reviewed starter snapshot |
| [Pluto TV and Samsung TV Plus XMLTV feeds](docs/catalog.md) | Separate program guide feeds matched to available starter channel IDs |
| M3U and Xtream Codes | Owner-configured live channels and provider movie/series libraries |
| [OwnTV](https://github.com/ahXN00/OwnTV) | Alternative player with a separate playlist, guide setup and private library |

## Configuration

| Setting | Default or behavior |
| --- | --- |
| First profile | Everyone, administrator; add household profiles and PINs in Settings |
| Starter playlists | Free live TV and Samsung TV Plus |
| Refresh interval | Six hours for fresh installs |
| Guide feeds | Pluto TV US and Samsung TV Plus US XMLTV |
| Movies and Series | Empty until a source supplies on-demand content |
| Provider setup | Add provider on Discover, or Settings > Playlists |
| Catalog management | Custom sources and removed presets are preserved across updates |
| Backup | Settings > Backup & Restore |
| Updates | In-app release checks or the toolkit's pinned installer |

Do not share provider passwords in chat, issues or committed playlists. Enter them locally in the app. See [catalog configuration](docs/catalog.md) for OwnTV's playlist and guide URLs.

## Updating and Removing

```bash
fire-iptv --install     # update from the toolkit's pinned release
fire-iptv --uninstall   # remove the app and its private library
```

Back up first if you need to preserve data before removal. The application ID differs from OpenIPTV, so both can remain installed. An old OpenIPTV installation is not automatically migrated. Export and restore its backup only if you want its existing sources and settings.

`firetv-revert --all` leaves fire-iptv and OwnTV installed to preserve their libraries. Select either player explicitly in the revert checklist to remove it. The legacy `firetv-iptv --install` and `--uninstall` commands without `--app` continue to target OwnTV.

## Commands

These commands belong to the companion toolkit and run on your computer.

| Command | Description | Options |
| --- | --- | --- |
| `fire-iptv` | Opens the guided player menu, defaulting to fire-iptv | `--app`, `--install`, `--uninstall`, `--yes`, `--help` |
| `firetv-iptv` | Opens the shared player menu; existing flag-only commands default to OwnTV | `--app`, `--install`, `--uninstall`, `--yes`, `--help` |
| `firetv-revert` | Reviews captured TV changes and optional app removal | See the [toolkit command reference](https://github.com/jeremykenedy/fire-tv-toolkit/blob/main/docs/COMMANDS.md) |

| Player option | Behavior |
| --- | --- |
| `--app=fire-iptv`, `--app=owntv` | Selects the player |
| `--install` | Installs or updates the selected player and opens it |
| `--uninstall` | Removes the selected player and its private library |
| `--yes` | Enables a scripted action; `--install` or `--uninstall` is still required |
| `--help`, `-h` | Prints the command's actual supported options |

## Testing

Use Flutter 3.47.7 and the Android toolchain described in [development](docs/development.md):

```bash
flutter pub get
python3 scripts/catalog.py --check
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

CI checks the catalog, Dart analysis, tests and the ARM Android build. Native guide and playback behavior must also be checked on a TV. Release signing uses a stable private key outside the repository; see [release builds](docs/development.md#signing).

## File Tree

```text
android/           Android application, native player and platform channels
art/               README banners and native TV screenshots
assets/catalog/    Starter streams, guides and snapshot manifest
assets/branding/   Application icon, splash and TV launcher artwork
docs/              Catalog, development and upstream reference documents
lib/               Flutter screens, application state and services
packages/          Local native engine integration
playlists/         Starter playlist for the separate OwnTV player
scripts/           Catalog validation and signed release builds
test/              Flutter behavior and regression tests
pubspec.yaml       Application version and dependency declarations
```

## Documentation

| Guide | Contents |
| --- | --- |
| [Documentation index](docs/index.md) | Every maintained guide and the inherited upstream references |
| [Catalog and providers](docs/catalog.md) | Starter sources, XMLTV matching, provider setup, OwnTV and snapshot maintenance |
| [Development](docs/development.md) | Toolchain, runtime packages, checks, architecture and signed release builds |

## Screenshots

Captured from the native application on a physical Fire TV. The starter has live TV; poster libraries appear after connecting a provider.

<table>
  <tr>
    <td colspan="2" valign="top"><a href="art/screenshots/discover-tv.png"><img src="art/screenshots/discover-tv.png" alt="Discover with TV guide, sports and provider setup tiles" title="Discover" width="320"></a></td>
    <td colspan="2" valign="top"><a href="art/screenshots/guide-tv.png"><img src="art/screenshots/guide-tv.png" alt="Live TV timeline with channel logos and program details" title="TV guide" width="320"></a></td>
    <td colspan="2" valign="top"><a href="art/screenshots/sports-tv.png"><img src="art/screenshots/sports-tv.png" alt="Sports guide filtered to available sports channels" title="Sports guide" width="320"></a></td>
  </tr>
  <tr>
    <td colspan="2" valign="top"><a href="art/screenshots/search-tv.png"><img src="art/screenshots/search-tv.png" alt="Native TV search with live channel results" title="Search" width="320"></a></td>
    <td colspan="2" valign="top"><a href="art/screenshots/provider-tv.png"><img src="art/screenshots/provider-tv.png" alt="Provider setup with M3U and Xtream Codes options" title="Provider setup" width="320"></a></td>
    <td colspan="2" valign="top"><a href="art/screenshots/settings-tv.png"><img src="art/screenshots/settings-tv.png" alt="Settings for playlists, profiles and the TV experience" title="Settings" width="320"></a></td>
  </tr>
  <tr>
    <td colspan="3" valign="top"><a href="art/screenshots/movies-tv.png"><img src="art/screenshots/movies-tv.png" alt="Movie library setup with a direct Add provider action" title="Movies" width="320"></a></td>
    <td colspan="3" valign="top"><a href="art/screenshots/series-tv.png"><img src="art/screenshots/series-tv.png" alt="TV series library setup explaining seasons and episodes" title="Series" width="320"></a></td>
  </tr>
</table>

## Upstream

fire-iptv is based on [OpenIPTV](https://github.com/Hunter-Clipper/OpenIPTV) v0.14.8. The original project provides the player, provider integrations, guide, profiles and much of the interface. This fork adds Fire TV discovery, the live-only starter, sports navigation, branding and toolkit installation. It retains the upstream history and GPL license. OwnTV is a separate application from [ahXN00/OwnTV](https://github.com/ahXN00/OwnTV).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and [Releases](https://github.com/jeremykenedy/fire-iptv/releases) for signed APKs, checksums and upgrade notes.

## License

This application is open-sourced software licensed under [GPL-3.0](LICENSE).

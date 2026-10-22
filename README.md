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

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Platform Support](#platform-support)
- [Documentation](#documentation)
- [Screenshots](#screenshots)
- [License](#license)

## Features

| Feature | Description | Guide |
| --- | --- | --- |
| Automatic live TV setup | Prepares the public live-channel starter and Everyone profile on first launch| [Details](docs/catalog.md) |
| Discover | TV guide, sports and provider setup tiles with visible remote focus| [Details](docs/catalog.md) |
| TV guide | Channel logos, categories, now/next programs, a timeline and live preview| [Details](docs/catalog.md) |
| Sports guide | Filters available football, baseball, basketball, racing, combat sports and other sports channels| [Details](docs/catalog.md) |
| Provider libraries | Imports M3U playlists/files or Xtream Codes sources supplied by the owner| [Details](docs/catalog.md) |
| Movies and series | Provider posters, genres, title details, seasons and episodes| [Details](docs/catalog.md) |
| Discovery actions | Recent releases from supplied release years, recommendations and a random movie action| [Details](docs/catalog.md) |
| Search | Finds available live channels, movies, series and guide programs| [Details](docs/catalog.md) |
| Favorites and progress | Saved favorites and Continue Watching for the active profile| [Details](docs/catalog.md) |
| Household profiles | Multiple sources, profiles and inherited parental controls| [Details](docs/catalog.md) |
| Local data | Encrypted credential storage and backup/restore| [Details](docs/catalog.md) |
| Catalog recovery | Bundled starter installation and refresh recovery that keeps the last working catalog| [Details](docs/catalog.md) |
| Application shortcuts | Opens installed Tubi and Plex applications for administrator profiles on TV| [Details](docs/catalog.md) |
| Toolkit installation | Checksum-verified installation and updates that preserve existing application data| [Details](docs/catalog.md) |

A public live-channel directory cannot supply every film, series, subscription network or premium sports event. [Catalog and provider documentation](docs/catalog.md) explains how the pieces fit together.

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

## Platform Support

| Platform | Requirements | Verification |
| --- | --- | --- |
| Fire TV | Android 7 / API 24 or newer; 32-bit or 64-bit ARM | Guide, sports, search, provider setup, playback and updates tested on a physical 32-bit Fire TV running API 30 |
| Android TV and Google TV | Android 7 / API 24 or newer; 32-bit or 64-bit ARM | Android APK compiled for both ARM targets; physical devices beyond the tested Fire TV remain unverified |

The published APK targets Android TVs. The separate [Fire TV Toolkit desktop app](https://github.com/jeremykenedy/fire-tv-toolkit/blob/main/docs/DESKTOP.md) runs on macOS, Windows and Linux to manage a connected TV.

## Documentation

| Guide | Contents |
| --- | --- |
| [Documentation index](docs/index.md) | Maintained guides and upstream references |
| [Catalog and providers](docs/catalog.md) | Starter channels, guide feeds and provider libraries |
| [Configuration and commands](docs/usage.md) | PiP defaults, backups, updates, removal and toolkit commands |
| [Integrations](docs/integrations.md) | Toolkit, OwnTV and preserved upstream attribution |
| [Development](docs/development.md) | Toolchain, architecture, tests and signed builds |
| [Native screenshots](docs/screenshots.md) | Current physical captures and clearly labeled historical routes |
| [1.1.1 update notes](docs/releases/v1.1.1.md) | Upgrade behavior and verification limits |
| [Changelog](CHANGELOG.md) | Release history |

## Screenshots

Signed 1.1.1/code 2 running on a physical Fire TV. See the [full gallery and capture provenance](docs/screenshots.md).

<table>
  <tr>
    <td><a href="art/screenshots/discover-1.1.1-fire-tv.png"><img src="art/screenshots/discover-1.1.1-fire-tv.png" alt="Discover and the existing live starter" width="320"></a></td>
    <td><a href="art/screenshots/settings-1.1.1-fire-tv.png"><img src="art/screenshots/settings-1.1.1-fire-tv.png" alt="Existing profile and two playlists after the signed update" width="320"></a></td>
    <td><a href="art/screenshots/pip-off-1.1.1-fire-tv.png"><img src="art/screenshots/pip-off-1.1.1-fire-tv.png" alt="Picture-in-Picture remains off after relaunch" width="320"></a></td>
  </tr>
</table>

## License

This application is open-sourced software licensed under [GPL-3.0](LICENSE).

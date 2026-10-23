# Release notes

## 1.2.0

Compatible TV launchers can show real live-channel cards with direct playback links. Cards follow the active playlist and profile restrictions, prioritize favorites and recent channels, and keep stream credentials inside the player. Android version code 3 preserves the existing package, signer and database. See the [upgrade guide](docs/releases/v1.2.0.md).

## 1.1.1

Picture-in-Picture defaults to off while explicitly saved choices are preserved. The Android update uses the existing package and production signer, with version code 2. See the [upgrade guide and verification](docs/releases/v1.1.1.md).

## 1.1.0

Documentation and README artwork update. The historical release has no Android asset, and its tagged application source still declares 1.0.0/code 1. Its tag and release remain unchanged.

## 1.0.0

The first fire-iptv release turns the OpenIPTV foundation into a Fire TV
starting point with an automatic live catalog, discovery tiles and a sports
guide. Movies and series come from a provider added by the owner.

### Upgrade guide

Install through `fire-iptv --install` in fire-tv-toolkit, or install the signed
`fire-iptv.apk` with ADB. Android 7 / API 24 or newer and an ARM processor are
required. The release includes 32-bit and 64-bit ARM code.

This is a new application ID, `com.jeremykenedy.fireiptv`. OpenIPTV and OwnTV
remain separate installations. There is no automatic migration of their
private settings. Use OpenIPTV's backup/restore if you intentionally want its
existing setup. A fresh install prepares the Everyone profile and live-only
starter; an imported setup is preserved. Export a backup before uninstalling.

### Breaking changes

None for existing fire-iptv users: this is the first release. Compared with the
upstream app, first launch now prepares public live-channel snapshots and
opens Discover. In-app updates use this repository's signed releases.

### Major changes

- Automatic live-only setup with 1,323 channels and two matched XMLTV feeds.
- Discover, All sports and a compact seven-item TV navigation rail.
- Provider-based poster libraries, recent releases, recommendations and random
  movie selection, respecting the active profile's visible library.
- Native Tubi and Plex shortcuts for TV administrators.
- A checksum-pinned toolkit installer and a compatible OwnTV starter playlist.

### Minor changes and fixes

- Navy and amber Fire TV branding and native launcher artwork.
- Atomic catalog updates, last-good cache recovery and preservation of custom
  sources, removed presets, profiles and favorites.
- Stable release signing without plaintext password files.
- Flutter analysis, behavior tests, catalog validation and Android compilation
  in CI.

### Verification and limitations

The native app was installed and exercised on a physical 32-bit Fire TV,
including first launch, guide data, sports filtering, search, provider setup, Tubi/Plex shortcuts and CBS Sports playback. An in-place signed update preserved the profile, sources and a saved channel favorite. Dart analysis and 265 tests passed, and CI compiled both ARM targets. The release APK
also compiles 64-bit ARM; that hardware is not physically tested. Catalog
counts describe the bundled snapshot. Stream availability and guide coverage
vary. No movie or series library is bundled, and proprietary app catalogs are
opened through their own apps. A provider with on-demand content is required
for integrated modern movies and series.

Source base: [OpenIPTV v0.14.8](https://github.com/Hunter-Clipper/OpenIPTV/tree/v0.14.8).

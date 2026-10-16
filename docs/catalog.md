# Catalog and providers

fire-iptv includes a snapshot of public live-channel links, with separate
Pluto TV and Samsung TV Plus XMLTV guides. It does not host video. The snapshot
contains 1,323 channels, including 226 channels classified as sports. Counts
describe the snapshot, not a promise that every stream works in every region.

The source URLs, revision and SHA-256 values are recorded in
[`assets/catalog/manifest.json`](../assets/catalog/manifest.json). Live links
come from [iptv-org](https://github.com/iptv-org/iptv). Guide feeds are maintained
by [Matt Huisman](https://github.com/matthuisman/i.mjh.nz).

## What appears on first launch

The app creates an Everyone profile, installs two live sources from bundled
assets, and starts fetching guide data in the background. Channel browsing
works without waiting for a guide download. Playing a stream requires network
access. Approximately 299 channel IDs match the two guide feeds in this
snapshot; other channels can still play without schedule data.

Starter sources refresh every six hours from this repository, keeping their
last working local copy when a request fails or a response is invalid. The
guide feeds refresh separately. Removing a starter source keeps it removed
across app updates. Updating an existing imported setup does not add starter
sources. Custom playlists, profiles, favorites and viewing progress remain
owned by the user.

## Movies and series

**Add provider** opens the native setup wizard. Add an M3U URL, a local M3U
file, or an Xtream Codes login from a service you use. An Xtream provider with
movie and series endpoints supplies the most complete library metadata.
Your provider determines titles, artwork, genres, seasons and availability.
Enter credentials on the TV; do not put them in a GitHub issue or playlist
committed to this repository.

Discover shows recent releases only when the supplied release year is the
current or previous year. Recommendations use available movies and viewing
preferences. Random chooses from the current profile's visible movie library.
Genre rows, posters, favorites, search and Continue Watching use that same
library. A guide cannot turn a live movie channel into an on-demand library.

The starter deliberately includes no public-domain movie collection. Old
Archive films do not stand in for a modern catalog. No free playlist supplies
every movie, series, premium sports event or subscription service.

Tubi and Plex buttons open their installed Android applications. Their
catalogs and account controls remain inside those apps. These shortcuts are
available to administrator profiles on a TV.

## OwnTV

Install OwnTV with `firetv-iptv --app=owntv --install`. Add this public playlist
through **Sources & guide > Playlists > Add Source > Remote**:

```text
https://raw.githubusercontent.com/jeremykenedy/fire-iptv/main/playlists/owntv.m3u
```

Then add both feeds under **EPG Sources**, select a six-hour refresh and sync:

```text
https://i.mjh.nz/PlutoTV/us.xml.gz
https://i.mjh.nz/SamsungTVPlus/us.xml.gz
```

Select the new playlist as the default. OwnTV's **TV Guide** displays live
programs; its Home view uses recent and favorite channels. Movies and series
require adding your provider separately in OwnTV. fire-iptv does not share its
private database or credentials with another application.

## Maintaining the snapshot

The M3U files are reviewed snapshots, not a proxy for upstream feeds. To update
them, use the public source URLs in the manifest, preserve stable channel IDs,
match guide IDs, remove dead links and keep only live HLS streams. Keep sports
categories under `Sports;Sports | <sport>` for fire-iptv. Increment the manifest
revision and update each file's SHA-256. Never include provider credentials,
personal profiles, watch history or an application backup.

Run these checks before committing a catalog update:

```bash
python3 scripts/catalog.py
python3 scripts/catalog.py --check
flutter test test/core/services/starter_catalog_test.dart
```

The script validates hashes and live-only entries, then builds the combined
OwnTV playlist with compatible category labels. Test guide alignment and real
playback on a TV after changing IDs or stream URLs. It does not assert that
every URL is reachable or that regional restrictions have disappeared.

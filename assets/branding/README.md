# fire-iptv native artwork

The native app uses navy `#101C30`, amber `#FFB54A` and white, with a TV/play
mark. These assets are application icons, splash artwork and a TV launcher
banner. They are separate from any optional repository README banner.

## Table of Contents

- [Assets](#assets)
- [Exporting](#exporting)
- [Legacy Artwork](#legacy-artwork)

## Assets

| File | Purpose |
| --- | --- |
| `icon.svg` | Full app icon |
| `icon_background.svg` | Adaptive icon background |
| `mark.svg` | Adaptive foreground, splash and in-app mark |
| `mark_mono.svg` | Monochrome icon |
| `wordmark.svg` | fire-iptv wordmark |
| `tv_banner.svg` | Android TV launcher banner |

## Exporting

Install librsvg, then export and regenerate Android icons and splash assets:

```bash
python3 assets/branding/export.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Legacy Artwork

Android is the validated platform for this fork. Legacy `icon_tile.svg` and
`readme_banner.svg` are retained from upstream as historical source artwork;
the exporter does not use them or generate a README banner.

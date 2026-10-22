# Configuration and toolkit commands

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
| Picture-in-Picture | Off when unset; an explicitly saved choice is preserved. Change it in Settings > Playback |
| Backup | Settings > Backup & Restore |
| Updates | In-app release checks or the toolkit's pinned installer |

Do not share provider passwords in chat, issues or committed playlists. Enter them locally in the app. See [catalog configuration](catalog.md) for OwnTV's playlist and guide URLs.

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

# Integrations and source attribution

| Integration | How it is used |
| --- | --- |
| [Fire TV Toolkit](https://github.com/jeremykenedy/fire-tv-toolkit) | Installs, updates, opens or removes the player over an authorized ADB connection |
| [iptv-org](https://github.com/iptv-org/iptv) | Public live-channel sources used to prepare the reviewed starter snapshot |
| [Pluto TV and Samsung TV Plus XMLTV feeds](catalog.md) | Separate program guide feeds matched to available starter channel IDs |
| M3U and Xtream Codes | Owner-configured live channels and provider movie/series libraries |
| [OwnTV](https://github.com/ahXN00/OwnTV) | Alternative player with a separate playlist, guide setup and private library |

## Upstream

fire-iptv is based on [OpenIPTV](https://github.com/Hunter-Clipper/OpenIPTV) v0.14.8. The original project provides the player, provider integrations, guide, profiles and much of the interface. This fork adds Fire TV discovery, the live-only starter, sports navigation, branding and toolkit installation. It retains the upstream history and GPL license. OwnTV is a separate application from [ahXN00/OwnTV](https://github.com/ahXN00/OwnTV).

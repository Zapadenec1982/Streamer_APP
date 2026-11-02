**English** · [Українська](README.uk.md)

# ModESP Streamer — phone app

A remote for the [ModESP Streamer](https://github.com/Zapadenec1982/ModESP_Streamer) network
player: what plays and from where, transport, volume, sources and the sound, and — later — speaker
measurements with the phone's microphone. Playback and DSP stay on the player; the phone controls
it and shows its state. Android first; iOS from the same code later.

The app has three sections, as the panel and its web interface do: **Player**, **Source** and
**Settings**. Until it talks to a real panel it runs a built-in demo panel; every title and name in
the demo is made up for it.

## Build

Flutter 3.47.9 (Dart 3.13.7), JDK 17, Android SDK with platform 36 and NDK 28.2.

```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --debug
```

## Shared with the firmware

Nothing the firmware already defines is written a second time:

| File | Made by | From the firmware |
|---|---|---|
| `lib/theme/m3_schemes.g.dart` | `tool/gen_theme.py` | the panel's colour schemes, `modules/ui_lvgl/src/ui_m3.cpp` (read by its own `tools/ui/web_tokens.py`) |
| `lib/l10n/app_<lang>.arb` | `tool/gen_l10n.py` | the web's catalogs `webui/src/i18n/<lang>.json`, the keys in `l10n/shared.txt`; app-only strings are in `l10n/app_<lang>.json` |
| `protocol/state_meta.json` | `tool/sync_state_meta.py` | the state keys, from the modules' manifests (`modules/<name>/manifest.json`) as `tools/generate_ui.py` projects them |
| `protocol/now_faces.json` | `tool/now_faces.mjs` (Node, local) | what the web shows for a state: the firmware's `webui/src/stores/now.js` run on the cases written there; the Dart port `lib/device/face.dart` is tested on it |
| `protocol/station_badges.json` | `tool/station_badges.mjs` (Node, local) | a station's stand-in disc: the firmware's `webui/src/lib/stationbadge.js` on the glass's pinned names and more; the Dart port `lib/ui/station_badge.dart` is tested on it |

The scripts read a firmware checkout named by `MODESP_PLAYER_ROOT` (default `../modesp-player`) and
take `--check`. `now_faces.mjs` also needs the firmware's `webui/node_modules`; CI tests only the
Dart side of it and of `station_badges.mjs`. `tool/firmware_ref` is the firmware commit CI checks
them against.

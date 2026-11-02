[English](README.md) · **Українська**

# ModESP Streamer — застосунок для телефона

Пульт для мережевого плеєра [ModESP Streamer](https://github.com/Zapadenec1982/ModESP_Streamer):
що грає і звідки, транспорт, гучність, джерела і звук, а згодом — вимір колонок мікрофоном
телефона. Відтворення й DSP лишаються на плеєрі; телефон керує ним і показує його стан. Спершу
Android; iOS — пізніше з того самого коду.

У застосунку три розділи, як на панелі і в її вебінтерфейсі: **Плеєр**, **Джерело** і
**Налаштування**. Поки він не говорить зі справжньою панеллю, працює вбудована демо-панель; усі
назви й імена в демо вигадані для нього.

## Збірка

Flutter 3.47.9 (Dart 3.13.7), JDK 17, Android SDK з платформою 36 і NDK 28.2.

```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --debug
```

## Спільне з прошивкою

Те, що вже визначає прошивка, вдруге не пишеться:

| Файл | Хто пише | З прошивки |
|---|---|---|
| `lib/theme/m3_schemes.g.dart` | `tool/gen_theme.py` | колірні схеми панелі, `modules/ui_lvgl/src/ui_m3.cpp` (читає її власний `tools/ui/web_tokens.py`) |
| `lib/l10n/app_<lang>.arb` | `tool/gen_l10n.py` | каталоги вебу `webui/src/i18n/<lang>.json`, ключі зі `l10n/shared.txt`; рядки лише застосунку — у `l10n/app_<lang>.json` |
| `protocol/state_meta.json` | `tool/sync_state_meta.py` | ключі стану з маніфестів модулів (`modules/<name>/manifest.json`), як їх проєктує `tools/generate_ui.py` |
| `protocol/now_faces.json` | `tool/now_faces.mjs` (Node, локально) | що показує веб для стану: `webui/src/stores/now.js` прошивки на записаних там випадках; на ньому тестується Dart-порт `lib/device/face.dart` |
| `protocol/station_badges.json` | `tool/station_badges.mjs` (Node, локально) | «диск» станції замість логотипа: `webui/src/lib/stationbadge.js` прошивки на закріплених іменах скла і ще кількох; на ньому тестується Dart-порт `lib/ui/station_badge.dart` |

Скрипти читають репозиторій прошивки, шлях до якого — `MODESP_PLAYER_ROOT` (за замовчуванням
`../modesp-player`), і приймають `--check`. `now_faces.mjs` потребує ще `webui/node_modules`
прошивки; CI перевіряє лише бік Dart — його і `station_badges.mjs`. `tool/firmware_ref` — коміт
прошивки, з яким їх звіряє CI.

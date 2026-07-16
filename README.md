# ai_language_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Development

### Resetting local state

The app persists state in a few places: the Gemini API key (secure
storage), `config.json` (theme, native/target language, difficulty level),
the in-progress learning session, and saved history files. For testing,
you can wipe any combination of these on startup with `--dart-define`
flags, applied in `main.dart` before normal startup routing runs.

| Flag | Clears |
| --- | --- |
| `RESET_APP=true` | Everything: API key, config.json, session state, history, and handoff files |
| `RESET_KEY=true` | Only the API key |
| `RESET_SESSION=true` | Only the in-progress session state |
| `RESET_HISTORY=true` | Only the saved history files |

Flags can be combined; each applies independently, and any flag not passed
leaves that data untouched. Examples:

```
# Full reset — back to ApiKeyScreen with nothing saved
flutter run --dart-define=RESET_APP=true

# Re-test the API key screen only, keep language/level/history
flutter run --dart-define=RESET_KEY=true

# Clear a stuck/in-progress session without losing history
flutter run --dart-define=RESET_SESSION=true

# Combine flags freely
flutter run --dart-define=RESET_KEY=true --dart-define=RESET_SESSION=true
```

Each run prints what was cleared and what was preserved, e.g.:

```
[RESET] Cleared: API Key, session state. Preserved: config.json, history, handoff files.
```

The same underlying `clear*` methods (`ApiKeyStorageService.clearApiKey`,
`ConfigService.clearConfig`, `SessionStateService.clearSession`,
`HistoryService.clearHistory`, `HandoffService.clearHandoffFiles`) back
both these flags and the "Reset All Data" button in the Settings dialog,
so there's one place each kind of reset is actually implemented.

# API Key 화면만 다시 테스트 (언어·레벨테스트 결과는 유지)
flutter run -d windows --dart-define=RESET_KEY=true

# 세션만 초기화해서 첫 문장부터 다시
flutter run -d windows --dart-define=RESET_SESSION=true

# 완전 초기화 (기존과 동일)
flutter run -d windows --dart-define=RESET_APP=true
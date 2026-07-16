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

### Daily learning limit & TTS caching

Gemini's free-tier TTS quota is small, so the app self-limits to stay
within it:

- **10 turns/day** (5 shadowing + 5 writing). Completing the 10th turn
  auto-finalizes the session exactly like "학습 종료" would. The current
  count shows as "Today: N/10" in each learning screen's AppBar.
- **One TTS call per sentence.** Synthesized audio is cached on disk
  (`tts_cache/`, keyed by sentence + target language) and only fetched lazily
  when the play button is first tapped — replays, retries, and resuming a
  session across app restarts all reuse the cached clip instead of calling
  Gemini again. Capped at 100 cached sentences, least-recently-used evicted
  first.
- Each newly-synthesized sentence gets a random voice from the official
  Gemini TTS voice list (`lib/constants/tts_voices.dart`); a cached replay
  keeps whatever voice it was first synthesized with.

### Resetting local state

The app persists state in a few places: the Gemini API key (secure
storage), `config.json` (theme, native/target language, difficulty level),
the in-progress learning session, saved history files, today's turn
counter (`daily_progress.json`), and the cached TTS audio (`tts_cache/`).
For testing, you can wipe any combination of these on startup with
`--dart-define` flags, applied in `main.dart` before normal startup
routing runs.

| Flag | Clears |
| --- | --- |
| `RESET_APP=true` | Everything: API key, config.json, session state, history, handoff files, the daily turn counter, and the TTS cache |
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
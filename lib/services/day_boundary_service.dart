import 'package:timezone/timezone.dart' as tz;

/// Single source of truth for "what day is it" throughout the app.
///
/// Every "today"/"same day" decision here (daily TTS turn limit, resuming
/// vs. finalizing a session, review-progress staleness, per-day history
/// filenames) is now defined as a **Pacific-time calendar day**, not the
/// device's local calendar day — because that's when Gemini's free-tier
/// daily quota actually resets. A learner outside the US can otherwise
/// have the app's "today" flip hours before or after the quota itself
/// does, in either direction. `America/Los_Angeles` (rather than a fixed
/// UTC-8 offset) is used specifically so this stays correct across DST
/// transitions.
///
/// Requires `package:timezone/data/latest.dart`'s `initializeTimeZones()`
/// to have been called once at app startup (see `main.dart`) — without it,
/// `tz.getLocation` throws.
class DayBoundaryService {
  static final _pacific = tz.getLocation('America/Los_Angeles');

  /// The Pacific calendar date (midnight, no time-of-day component) that
  /// [instant] falls in.
  DateTime pacificDateOf(DateTime instant) {
    final pacific = tz.TZDateTime.from(instant, _pacific);
    return DateTime(pacific.year, pacific.month, pacific.day);
  }

  /// The Pacific calendar date "right now".
  DateTime currentPacificDate() => pacificDateOf(DateTime.now());

  /// True if [a] and [b] fall on the same Pacific calendar day.
  bool isSamePacificDay(DateTime a, DateTime b) => pacificDateOf(a) == pacificDateOf(b);
}

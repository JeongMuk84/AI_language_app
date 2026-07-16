/// Minimum pronunciation match rate (0-100, from `analyzePronunciation`)
/// required before "Continue" unlocks on the shadowing/writing pronunciation
/// screens. Below this, the learner must re-record and try again.
const double kPronunciationPassThreshold = 85;

/// How many of the most recent conversation turns get sent as context to
/// `generateNextSentence`. Recent context is enough for a natural-sounding
/// continuation — sending the whole session's history makes every prompt
/// larger (and slower/more expensive) the longer a session runs.
const int kHistoryContextWindow = 6;

/// Max completed turns (shadowing + writing combined) per local calendar
/// day — 5 shadowing + 5 writing. Keeps daily TTS usage within the Gemini
/// free tier's per-day quota (one synthesis per sentence, one sentence per
/// turn). Reaching this auto-finalizes the session, same as "학습 종료".
const int kDailyTurnLimit = 10;

/// Turns "turns completed so far today" (0-[kDailyTurnLimit]) into what the
/// AppBar shows — "which turn the learner is currently on", 1-indexed (0
/// completed → showing "1", meaning the first sentence is in progress).
/// Capped at [kDailyTurnLimit] so it never briefly reads e.g. "11/10" in
/// the moment after the last turn completes and before the app navigates
/// away to finalize the session.
int displayedDailyTurnNumber(int completedCount) {
  final current = completedCount + 1;
  return current > kDailyTurnLimit ? kDailyTurnLimit : current;
}

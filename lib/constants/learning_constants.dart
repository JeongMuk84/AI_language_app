/// Minimum pronunciation match rate (0-100, from `analyzePronunciation`)
/// required before "Continue" unlocks on the shadowing/writing pronunciation
/// screens. Below this, the learner must re-record and try again.
const double kPronunciationPassThreshold = 85;

/// How many of the most recent conversation turns get sent as context to
/// `generateNextSentence`. Recent context is enough for a natural-sounding
/// continuation — sending the whole session's history makes every prompt
/// larger (and slower/more expensive) the longer a session runs.
const int kHistoryContextWindow = 6;

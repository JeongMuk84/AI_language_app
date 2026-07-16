import 'dart:math';

/// All 30 prebuilt Gemini TTS voice names, per the official voice list
/// (https://ai.google.dev/gemini-api/docs/speech-generation). Picking a
/// fresh one per newly-synthesized sentence (see `GeminiService.speakCached`)
/// gives some variety instead of every sentence sounding identical.
///
/// Some voices may sound noticeably worse than others in a given target
/// language (this hasn't been verified against every language this app
/// might be used for) — if a learner reports an odd/unnatural voice for
/// their language, narrowing this list per-language is the fix.
const List<String> kGeminiTtsVoices = [
  'Zephyr',
  'Puck',
  'Charon',
  'Kore',
  'Fenrir',
  'Leda',
  'Orus',
  'Aoede',
  'Callirrhoe',
  'Autonoe',
  'Enceladus',
  'Iapetus',
  'Umbriel',
  'Algieba',
  'Despina',
  'Erinome',
  'Algenib',
  'Rasalgethi',
  'Laomedeia',
  'Achernar',
  'Alnilam',
  'Schedar',
  'Gacrux',
  'Pulcherrima',
  'Achird',
  'Zubenelgenubi',
  'Vindemiatrix',
  'Sadachbia',
  'Sadaltager',
  'Sulafat',
];

final Random _voiceRandom = Random();

/// Picks a uniformly random voice from [kGeminiTtsVoices]. Called once per
/// newly-synthesized (cache-miss) sentence — a cache hit reuses whatever
/// voice that sentence was originally synthesized with.
String randomTtsVoice() => kGeminiTtsVoices[_voiceRandom.nextInt(kGeminiTtsVoices.length)];

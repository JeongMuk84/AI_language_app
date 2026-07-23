import 'dart:math';

/// Gemini TTS 공식 음성 목록(https://ai.google.dev/gemini-api/docs/speech-generation)
/// 에 포함된, 사전 제작된(prebuilt) 30개 음성 이름 전체. 새로 합성하는
/// 문장마다(cache miss일 때, `GeminiService.speakCached` 참고) 매번 새로운
/// 음성을 고르면 모든 문장이 똑같은 목소리로 들리지 않고 약간의 다양성을
/// 준다.
///
/// 특정 target language에서는 일부 음성이 다른 음성보다 눈에 띄게
/// 부자연스럽게 들릴 수 있다(이 앱이 지원하는 모든 언어에 대해
/// 검증되지는 않았다) — 학습자가 특정 언어에서 이상하거나 부자연스러운
/// 음성을 신고하면, 이 목록을 언어별로 좁히는 것이 해결책이 된다.
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

/// [randomTtsVoice]가 사용하는, 이 파일 전용 `Random` 인스턴스.
final Random _voiceRandom = Random();

/// [kGeminiTtsVoices] 중에서 균등 확률로 무작위 음성 하나를 고른다.
/// 새로 합성되는(cache miss인) 문장마다 한 번씩 호출된다 — cache hit인
/// 경우에는 그 문장이 처음 합성될 때 쓰였던 음성을 그대로 재사용한다.
/// `GeminiService`의 `speakCached`가 cache miss 시 이 함수를 호출해
/// 이번 합성에 쓸 음성을 결정한다.
String randomTtsVoice() => kGeminiTtsVoices[_voiceRandom.nextInt(kGeminiTtsVoices.length)];

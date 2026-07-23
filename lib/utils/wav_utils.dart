import 'dart:typed_data';

/// 원본 16-bit PCM 오디오 샘플([pcmBytes])을 표준 44바이트 RIFF/WAVE
/// 헤더로 감싸서, `package:audioplayers`가 재생할 수 있는 형태로
/// 만든다(`audioplayers`는 원시 샘플이 아니라 인식 가능한 컨테이너
/// 포맷을 필요로 한다). Gemini의 TTS endpoint는 raw PCM을 반환하므로,
/// 이 함수가 그것을 재생 가능한 WAV로 바꿔주는 대응 짝(counterpart)
/// 역할을 한다. `GeminiService`가 TTS 합성 응답을 처리할 때 호출한다.
///
/// [sampleRate]는 PCM 샘플링 레이트(Hz), [numChannels]는 채널 수(기본
/// 모노 1채널)이다. 헤더와 원본 PCM 데이터를 이어붙인 `Uint8List`를
/// 반환한다.
Uint8List pcm16ToWav(
  Uint8List pcmBytes, {
  required int sampleRate,
  int numChannels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataLength = pcmBytes.length;

  final header = BytesBuilder();
  void writeAscii(String s) => header.add(s.codeUnits);
  void writeUint32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    header.add(b.buffer.asUint8List());
  }

  void writeUint16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    header.add(b.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + dataLength);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16); // fmt chunk size
  writeUint16(1); // PCM
  writeUint16(numChannels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeAscii('data');
  writeUint32(dataLength);

  final result = BytesBuilder();
  result.add(header.toBytes());
  result.add(pcmBytes);
  return result.toBytes();
}

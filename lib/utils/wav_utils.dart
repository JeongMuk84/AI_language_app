import 'dart:typed_data';

/// Wraps raw 16-bit PCM audio samples in a standard 44-byte RIFF/WAVE
/// header, so it can be played by [package:audioplayers] (which needs a
/// recognizable container, not bare samples). Gemini's TTS endpoint returns
/// raw PCM — this is the counterpart to that.
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

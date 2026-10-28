import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flatsphere/backend/voice_recorder.dart';

void main() {
  test('wavFromPcm writes a valid 16 kHz mono WAV header', () {
    final wav = wavFromPcm(Uint8List.fromList(List.filled(100, 1)));
    final d = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(d.getUint32(4, Endian.little), 136);
    expect(d.getUint32(24, Endian.little), 16000);
    expect(d.getUint16(22, Endian.little), 1);
    expect(d.getUint32(40, Endian.little), 100);
    expect(wav.length, 144);
  });
}

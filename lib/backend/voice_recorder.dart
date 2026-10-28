import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:record/record.dart';

import 'complaints_repo.dart' show VoiceFormat, wavVoiceFormat, webmVoiceFormat, m4aVoiceFormat;
import 'upload_preparation.dart' show maxUploadBytes;

const maxVoiceDuration = Duration(minutes: 3);
const _sampleRate = 16000;

/// 44-byte WAV header followed by 16-bit mono PCM.
Uint8List wavFromPcm(Uint8List pcm, {int sampleRate = _sampleRate}) {
  final header = ByteData(44);
  void tag(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)..add(header.buffer.asUint8List())..add(pcm)).takeBytes();
}

/// Records a voice note. Browsers record Opus/AAC (small files) through MediaRecorder; otherwise raw PCM is
/// streamed and wrapped as WAV. The record package only allows PCM for streaming, so the two paths differ.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _limit;
  bool _streaming = false;
  bool _tooLarge = false;
  VoiceFormat _format = wavVoiceFormat;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// [onAutoStop] fires when the time or size cap is hit; the caller should then call [stop].
  Future<void> start({required void Function() onAutoStop, required void Function(Object error) onError}) async {
    _pcm.clear();
    _tooLarge = false;
    _streaming = false;
    _format = wavVoiceFormat;
    RecordConfig? compressed;
    if (kIsWeb) {
      if (await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        compressed = const RecordConfig(encoder: AudioEncoder.opus, sampleRate: _sampleRate, numChannels: 1, bitRate: 24000);
        _format = webmVoiceFormat;
      } else if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
        compressed = const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: _sampleRate, numChannels: 1, bitRate: 32000);
        _format = m4aVoiceFormat;
      }
    }
    if (compressed != null) {
      await _recorder.start(compressed, path: '');
    } else {
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate, numChannels: 1),
      );
      _streaming = true;
      _sub = stream.listen(
        (bytes) {
          _pcm.add(bytes);
          if (_pcm.length > maxUploadBytes - 44 && !_tooLarge) {
            _tooLarge = true;
            onAutoStop();
          }
        },
        onError: onError,
      );
    }
    _limit = Timer(maxVoiceDuration, onAutoStop);
  }

  Future<({Uint8List bytes, VoiceFormat format})> stop() async {
    _limit?.cancel();
    final path = await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    Uint8List bytes;
    if (_streaming) {
      bytes = wavFromPcm(_pcm.takeBytes());
    } else {
      if (path == null || path.isEmpty) throw StateError('No audio was captured');
      bytes = await XFile(path).readAsBytes();
    }
    if (bytes.length <= (_streaming ? 44 : 0)) throw StateError('No audio was captured');
    if (bytes.length > maxUploadBytes) throw StateError('Voice note exceeded the 5 MB upload limit');
    return (bytes: bytes, format: _format);
  }

  Future<void> dispose() async {
    _limit?.cancel();
    await _sub?.cancel();
    await _recorder.dispose();
  }
}

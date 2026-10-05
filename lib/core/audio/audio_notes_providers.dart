import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'audio_capture_file.dart' as files;
import 'tasting_audio.dart';

class CapturedAudio {
  const CapturedAudio(this.bytes, this.mimeType, this.durationMs);
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  String get extension => TastingAudio.extensions[mimeType]!;
}

abstract interface class AudioNotesDevice {
  Future<int> start(); // maximum seconds for this encoder
  Future<void> pause();
  Future<void> resume();
  Future<CapturedAudio> stop();
  Future<void> cancel();
  Future<void> play(Uint8List bytes, String mimeType);
  Future<void> stopPlayback();
  Stream<void> get playbackEnded;
  Future<void> dispose();
}

class PlatformAudioNotesDevice implements AudioNotesDevice {
  AudioRecorder? _recordingDevice;
  AudioPlayer? _playbackDevice;
  AudioRecorder get _recorder => _recordingDevice ??= AudioRecorder();
  AudioPlayer get _player {
    if (_playbackDevice == null) {
      _playbackDevice = AudioPlayer();
      _complete = _playbackDevice!.onPlayerComplete.listen(
        (_) => _ended.add(null),
      );
    }
    return _playbackDevice!;
  }

  final _ended = StreamController<void>.broadcast();
  StreamSubscription<void>? _complete;
  final _time = Stopwatch();
  String? _path;
  String _mime = 'audio/mp4';
  @override
  Stream<void> get playbackEnded => _ended.stream;
  @override
  Future<int> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone permission was denied. Enable microphone access in your device or browser settings.',
      );
    }
    var encoder = AudioEncoder.aacLc;
    _mime = 'audio/mp4';
    if (!await _recorder.isEncoderSupported(encoder)) {
      if (kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;
        _mime = 'audio/webm';
      } else {
        encoder = AudioEncoder.wav;
        _mime = 'audio/wav';
      }
    }
    _path = await files.capturePath(TastingAudio.extensions[_mime]!);
    try {
      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
      _time
        ..reset()
        ..start();
      // WAV is uncompressed; end before the per-recording byte ceiling.
      return encoder == AudioEncoder.wav ? 900 : 7200;
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    await _recorder.pause();
    _time.stop();
  }

  @override
  Future<void> resume() async {
    await _recorder.resume();
    _time.start();
  }

  @override
  Future<CapturedAudio> stop() async {
    _time.stop();
    final path = await _recorder.stop();
    if (path == null) throw StateError('The recorder returned no audio.');
    _path = path;
    final data = await files.readCapture(
      path,
      TastingAudioStore.maxRecordingBytes * 2,
    );
    final mime = data.mime ?? _mime;
    if (!TastingAudioStore.hasContainer(mime, data.bytes)) {
      throw StateError('The recorder returned an unsupported audio format.');
    }
    final capture = CapturedAudio(
      data.bytes,
      mime,
      _time.elapsedMilliseconds.clamp(1, 7200000),
    );
    await files.removeCapture(path);
    _path = null;
    return capture;
  }

  @override
  Future<void> cancel() async {
    _time.stop();
    await _recordingDevice?.cancel();
    if (_path != null) await files.removeCapture(_path!);
    _path = null;
  }

  @override
  Future<void> play(Uint8List bytes, String mimeType) =>
      _player.play(BytesSource(bytes, mimeType: mimeType));
  @override
  Future<void> stopPlayback() async {
    await _playbackDevice?.stop();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recordingDevice?.dispose();
    await _complete?.cancel();
    await _playbackDevice?.dispose();
    await _ended.close();
  }
}

final tastingAudioStoreProvider = Provider(
  (ref) => TastingAudioStore(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);
final tastingAudioProvider = StreamProvider.family<List<TastingAudio>, String>(
  (ref, id) => ref.watch(tastingAudioStoreProvider).watch(id),
);

/// Override with a fake device in UI tests; one recorder/player per notes panel.
final audioNotesDeviceFactoryProvider = Provider<AudioNotesDevice Function()>(
  (ref) => PlatformAudioNotesDevice.new,
);

/// Route/finish/delete guards query live callbacks, including pending saves.
final unsavedAudioProvider = Provider<Map<String, bool Function()>>(
  (ref) => {},
);

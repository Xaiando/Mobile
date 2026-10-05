// Native codec/plugin check. It never starts a microphone recording.
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';

Uint8List silentWav() {
  final bytes = Uint8List(32044);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  bytes.setRange(36, 40, ascii.encode('data'));
  final data = ByteData.sublistView(bytes);
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, 32000, Endian.little);
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native audio plugins initialize and finish silent byte playback',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Isolated audio plugin check')),
        ),
      );
      await tester.runAsync(() async {
        final recorder = AudioRecorder();
        final player = AudioPlayer();
        try {
          expect(await recorder.isEncoderSupported(AudioEncoder.aacLc), isTrue);
          expect(await recorder.isRecording(), isFalse);
          await player.setVolume(0);
          final ended = player.onPlayerComplete.first.timeout(
            const Duration(seconds: 15),
          );
          await player.play(BytesSource(silentWav(), mimeType: 'audio/wav'));
          final duration = await player.getDuration();
          expect(duration, isNotNull);
          expect(duration!.inMilliseconds, greaterThanOrEqualTo(900));
          await ended;
          expect(player.state, PlayerState.completed);
          await player.stop();
          debugPrint(
            'NATIVE_AUDIO: AAC supported; one-second silent WAV completed; no microphone captured.',
          );
        } finally {
          await recorder.dispose();
          await player.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}

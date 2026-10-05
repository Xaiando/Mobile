import 'dart:typed_data';

Future<String> capturePath(String extension) async =>
    throw UnsupportedError('Audio is unavailable.');
Future<({Uint8List bytes, String? mime})> readCapture(
  String path,
  int maxBytes,
) async => throw UnsupportedError('Audio is unavailable.');
Future<void> removeCapture(String path) async {}
Future<void> clearCaptureStaging() async {}

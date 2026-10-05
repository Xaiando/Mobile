import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> capturePath(String extension) async => '';
Future<({Uint8List bytes, String? mime})> readCapture(
  String path,
  int maxBytes,
) async {
  if (!path.startsWith('blob:')) throw StateError('Unexpected recording URL.');
  final response = await web.window.fetch(path.toJS).toDart;
  final blob = await response.blob().toDart;
  if (blob.size > maxBytes) {
    throw StateError('The recording exceeds ${maxBytes ~/ (1024 * 1024)} MiB.');
  }
  final buffer = await blob.arrayBuffer().toDart;
  return (bytes: buffer.toDart.asUint8List(), mime: blob.type.split(';').first);
}

Future<void> removeCapture(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}

Future<void> clearCaptureStaging() async {}

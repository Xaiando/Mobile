import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../database/uuid.dart';

final _owned = <String>{};
Future<String> capturePath(String extension) async {
  final root = await getTemporaryDirectory();
  final path =
      '${root.path}${Platform.pathSeparator}sommelier-audio-${newUuid()}.$extension';
  _owned.add(path);
  return path;
}

Future<({Uint8List bytes, String? mime})> readCapture(
  String path,
  int maxBytes,
) async {
  if (!_owned.contains(path)) throw StateError('Unexpected recording path.');
  final file = File(path);
  if (await file.length() > maxBytes) {
    throw StateError('The recording exceeds ${maxBytes ~/ (1024 * 1024)} MiB.');
  }
  return (bytes: await file.readAsBytes(), mime: null);
}

Future<void> removeCapture(String path) async {
  if (!_owned.contains(path)) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
  _owned.remove(path);
}

/// Erase All only removes files from this app's recording filename namespace.
/// Direct children only; never follow links or recursively delete a directory.
Future<void> clearCaptureStaging() async {
  final root = Directory((await getTemporaryDirectory()).path).absolute;
  final ownedName = RegExp(
    r'^sommelier-audio-[0-9a-f-]{36}\.(m4a|webm|ogg|wav)$',
  );
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! File || entity.parent.absolute.path != root.path) continue;
    final name = entity.uri.pathSegments.last;
    if (ownedName.hasMatch(name)) {
      await entity.delete();
      _owned.remove(entity.path);
    }
  }
}

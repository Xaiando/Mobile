import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PortableFiles {
  Future<bool> save(String name, Uint8List bytes, String mimeType);
}

class PlatformPortableFiles implements PortableFiles {
  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async =>
      await FilePicker.saveFile(
        dialogTitle: 'Download for your records',
        fileName: name,
        bytes: bytes,
        mimeType: mimeType,
      ) !=
      null;
}

final portableFilesProvider = Provider<PortableFiles>(
  (ref) => PlatformPortableFiles(),
);

import 'dart:typed_data';

import 'recovered_scan_file.dart';

/// Web cannot receive Android image_picker lost data.
bool get isAndroidRecoveryPlatform => false;

class RecoveredScanStorage {
  RecoveredScanStorage({String? rootPath, String? pickerCacheRootPath});

  Future<List<RecoveredScanFile>> list() async => const [];

  Future<RecoveredScanFile> stage(Uint8List bytes) =>
      throw UnsupportedError('Android photo recovery is unavailable.');

  Future<Uint8List> read(String id) =>
      throw UnsupportedError('Android photo recovery is unavailable.');

  Future<void> discard(String id) async {}

  Future<String?> recordPickerCachePath(String path) async => null;

  Future<bool> beginLostResult() async => false;

  Future<bool> pickerPathExists(String path) async => false;

  Future<void> completeLostResult() async {}

  Future<List<String>> pendingPickerCachePaths() async => const [];

  Future<void> forgetPickerCachePath(String canonicalPath) async {}

  Future<void> clearAll() async {}
}

/// Erase All hook; a no-op outside platforms with a private file store.
Future<void> clearRecoveredScanStaging() async {}

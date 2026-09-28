import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Uses a picker image, then removes only an app-owned temporary copy.
/// The picker path must remain available until OCR has read it. Cleanup also
/// runs when decoding or recognition fails, and never replaces that error.
Future<T> withPickedTemporaryPhoto<T>(
  String path,
  Future<T> Function() action, {
  String? temporaryDirectoryPath,
}) async {
  try {
    return await action();
  } finally {
    await removePickedTemporaryPhoto(
      path,
      temporaryDirectoryPath: temporaryDirectoryPath,
    );
  }
}

/// Returns false if [path] is outside app temporary storage or cleanup fails.
/// Resolving both paths prevents a symlink in the cache from deleting a user
/// file elsewhere. A failed best-effort delete must not hide a scan error.
Future<bool> removePickedTemporaryPhoto(
  String path, {
  String? temporaryDirectoryPath,
  String? iosPickerTemporaryDirectoryPath,
  String? applicationDocumentsDirectoryPath,
}) async {
  try {
    final temporary = temporaryDirectoryPath == null
        ? await getTemporaryDirectory()
        : Directory(temporaryDirectoryPath);
    final target = await File(path).resolveSymbolicLinks();
    final cacheRoot = await temporary.resolveSymbolicLinks();
    if (_isInside(target, cacheRoot)) {
      await File(target).delete();
      return true;
    }

    // path_provider's temporary directory is Library/Caches on iOS, but
    // image_picker_ios writes its returned image to NSTemporaryDirectory()
    // (the app container's tmp sibling). Never accept a global/system tmp:
    // the picker root must first resolve inside this app's own container.
    if (!Platform.isIOS && iosPickerTemporaryDirectoryPath == null) {
      return false;
    }
    final documents = applicationDocumentsDirectoryPath == null
        ? await getApplicationDocumentsDirectory()
        : Directory(applicationDocumentsDirectoryPath);
    final appContainer = await documents.parent.resolveSymbolicLinks();
    final pickerTemp = iosPickerTemporaryDirectoryPath == null
        ? Directory.systemTemp
        : Directory(iosPickerTemporaryDirectoryPath);
    final pickerRoot = await pickerTemp.resolveSymbolicLinks();
    if (!_isInside(pickerRoot, appContainer) ||
        !_isInside(target, pickerRoot)) {
      return false;
    }
    await File(target).delete();
    return true;
  } catch (_) {
    return false;
  }
}

bool _isInside(String path, String root) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix);
}

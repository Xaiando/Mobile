import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'journal_photo_store.dart';
import 'recovered_scan_storage.dart';

typedef _PickerPath = ({String path, bool appOwned, bool inventoried});

/// Moves Android lost-picker results out of cache before any editor opens.
/// The app's scanner is the only image_picker caller and uses pickImage.
class JournalScanRecovery {
  JournalScanRecovery({
    ImagePicker? picker,
    RecoveredScanStorage? storage,
    Future<bool> Function(String path)? cleanupPickerFile,
    bool? androidRuntime,
  }) : _picker = picker ?? ImagePicker(),
       storage = storage ?? RecoveredScanStorage(),
       _cleanupPickerFile = cleanupPickerFile ?? _noCleanup,
       androidRuntime = androidRuntime ?? isAndroidRecoveryPlatform;

  final ImagePicker _picker;
  final RecoveredScanStorage storage;
  final Future<bool> Function(String path) _cleanupPickerFile;
  final bool androidRuntime;
  bool _checked = false;
  Future<void>? _inFlight;
  Future<void>? _eraseInFlight;
  final _pickerPathsNeedingCleanup = <String>{};
  String? warning;

  static Future<bool> _noCleanup(String path) async => false;

  static const _cleanupWarning =
      'An interrupted picker photo remains in temporary device storage. '
      'Close and reopen the app to retry cleanup.';
  static const _manualCleanupWarning =
      'An interrupted picker photo still needs device cleanup. '
      'Clear this app\'s storage in Android settings to remove its '
      'remaining local files.';

  /// Only paths recorded on an earlier launch may be retried here. The
  /// current native result has not been consumed yet, so this cannot delete
  /// an image whose staging is about to fail on this launch. A failed stage
  /// also leaves the lost-result sentinel unresolved, which prevents this
  /// inventory read on later launches until the device is cleared.
  Future<void> _retryInventoriedPickerCleanup() async {
    final List<String> paths;
    try {
      paths = await storage.pendingPickerCachePaths();
    } catch (_) {
      warning = _cleanupWarning;
      return;
    }
    for (final path in paths) {
      try {
        if (await _cleanupPickerFile(path)) {
          await storage.forgetPickerCachePath(path);
          continue;
        }
      } catch (_) {
        // Retain the durable inventory for the next launch or Erase All.
      }
      warning = _cleanupWarning;
    }
  }

  Future<_PickerPath> _rememberPickerPath(String path) async {
    try {
      final recorded = await storage.recordPickerCachePath(path);
      // Null means the source could not be inventoried as app-cache data.
      // An existing outside-cache path is still unresolved unless guarded
      // cleanup can prove it absent without deleting an external file.
      if (recorded == null) {
        return (
          path: path,
          appOwned: await storage.pickerPathExists(path),
          inventoried: false,
        );
      }
      return (path: recorded, appOwned: true, inventoried: true);
    } catch (_) {
      // An inventory failure is not evidence that the file is external.
      // The pre-retrieval sentinel remains until guarded cleanup succeeds.
      return (path: path, appOwned: true, inventoried: false);
    }
  }

  Future<void> _finishLostResult({required bool unresolved}) async {
    if (unresolved) {
      warning = _manualCleanupWarning;
      return;
    }
    try {
      await storage.completeLostResult();
    } catch (_) {
      warning = _manualCleanupWarning;
    }
  }

  /// Erase All takes precedence over an image_picker result left by a killed
  /// activity. Consume that result without staging it, then let the backup
  /// service clear the dedicated recovery directory.
  Future<void> discardLostAfterErase() {
    if (!androidRuntime) return Future<void>.value();
    if (_eraseInFlight case final running?) return running;
    final task = _discardLostAfterEraseOnce();
    _eraseInFlight = task;
    return task.whenComplete(() {
      if (identical(_eraseInFlight, task)) _eraseInFlight = null;
    });
  }

  Future<void> _discardLostAfterEraseOnce() async {
    // Erase All can be triggered while startup is still sanitizing a lost
    // result. Wait for that stage before the caller clears its directory.
    if (_inFlight case final running?) await running;
    if (!_checked) {
      _checked = true;
      final task = _retrieveLostForErase();
      _inFlight = task;
      try {
        await task;
      } catch (_) {
        // Retry if marker creation failed before the native call. If the
        // result was consumed, the existing sentinel keeps an empty retry
        // from being mistaken for successful cleanup.
        _checked = false;
        rethrow;
      } finally {
        if (identical(_inFlight, task)) _inFlight = null;
      }
    }
    final paths = {
      ..._pickerPathsNeedingCleanup,
      ...await storage.pendingPickerCachePaths(),
    };
    for (final path in paths) {
      // A failed guarded deletion keeps both the storage inventory and the
      // same-transaction database erase marker for a later retry.
      if (!await _cleanupPickerFile(path)) {
        throw StateError('An interrupted picker photo could not be cleared.');
      }
      await storage.forgetPickerCachePath(path);
      _pickerPathsNeedingCleanup.remove(path);
    }
  }

  Future<void> _retrieveLostForErase() async {
    // Write before the native call: it consumes the lost result even if the
    // process dies before any returned path reaches the durable inventory.
    final wasUnresolved = await storage.beginLostResult();
    final response = await _picker.retrieveLostData();
    final files = response.files?.isNotEmpty == true
        ? response.files!
        : (response.file == null ? <XFile>[] : <XFile>[response.file!]);
    if (wasUnresolved && files.isEmpty) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    for (final file in files) {
      final remembered = await _rememberPickerPath(file.path);
      if (!remembered.appOwned) {
        // The guarded cleaner may confirm an already-missing synthetic path;
        // it cannot delete a real path outside app-owned temporary storage.
        try {
          await _cleanupPickerFile(file.path);
        } catch (_) {}
        continue;
      }
      _pickerPathsNeedingCleanup.add(remembered.path);
      if (!remembered.inventoried) {
        if (!await _cleanupPickerFile(remembered.path)) {
          throw StateError('An interrupted picker photo could not be cleared.');
        }
        _pickerPathsNeedingCleanup.remove(remembered.path);
      }
    }
    // A later result says nothing about a different result consumed before
    // this marker survived a restart. Keep that unknown path fail-closed.
    if (wasUnresolved) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    await storage.completeLostResult();
  }

  /// This may be called more than once by startup dependents, but only asks
  /// the Android plugin once for a result already consumed by its native API.
  Future<void> recoverAtStartup() {
    if (!androidRuntime) return Future<void>.value();
    if (_inFlight case final running?) return running;
    if (_checked) return Future<void>.value();
    _checked = true;
    final task = _recoverOnce();
    _inFlight = task;
    return task.whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
  }

  Future<void> _recoverOnce() async {
    await _retryInventoriedPickerCleanup();
    final bool wasUnresolved;
    try {
      wasUnresolved = await storage.beginLostResult();
    } catch (_) {
      _checked = false;
      warning = 'An interrupted picker result needs device cleanup.';
      return;
    }
    LostDataResponse response;
    try {
      response = await _picker.retrieveLostData();
    } catch (_) {
      _checked = false;
      warning = 'An interrupted photo selection could not be checked.';
      return;
    }
    if (response.isEmpty) {
      await _finishLostResult(unresolved: wasUnresolved);
      return;
    }
    final files = response.files?.isNotEmpty == true
        ? response.files!
        : (response.file == null ? <XFile>[] : <XFile>[response.file!]);
    if (files.isEmpty) {
      if (response.exception != null) {
        warning = 'An interrupted photo selection did not return a photo.';
      }
      await _finishLostResult(unresolved: wasUnresolved);
      return;
    }
    final isImage =
        response.type == null || response.type == RetrieveType.image;
    var failed = 0;
    var unresolved = false;
    for (final file in files) {
      final remembered = await _rememberPickerPath(file.path);
      var staged = false;
      try {
        if (!isImage) {
          throw const PhotoStoreException(
            'Interrupted selection was not an image.',
          );
        }
        if (await file.length() > JournalPhotoStore.maxImportBytes) {
          throw const PhotoStoreException('Recovered photo is too large.');
        }
        final sanitized = JournalPhotoStore.sanitize(await file.readAsBytes());
        await storage.stage(sanitized);
        staged = true;
      } catch (_) {
        failed++;
      }
      // Only a successful durable stage may release an image's picker copy.
      // Non-images can be discarded by the same guarded cleaner.
      if (staged || !isImage) {
        try {
          if (await _cleanupPickerFile(remembered.path)) {
            if (remembered.inventoried) {
              await storage.forgetPickerCachePath(remembered.path);
            }
            continue;
          }
        } catch (_) {}
        if (staged) warning = _cleanupWarning;
      }
      if (remembered.appOwned) {
        _pickerPathsNeedingCleanup.add(remembered.path);
        // Inventory alone cannot prove that a failed image was staged. Keep
        // the pre-retrieval sentinel so a later startup never deletes the
        // only remaining copy under the successful-stage retry path.
        if (!remembered.inventoried || (isImage && !staged)) {
          unresolved = true;
        }
      }
    }
    await _finishLostResult(unresolved: wasUnresolved || unresolved);
    if (failed > 0) {
      if (unresolved) {
        warning =
            'Some interrupted photos could not be recovered. '
            '$_manualCleanupWarning';
      } else {
        warning ??= isImage
            ? 'Some interrupted photos could not be recovered. '
                  'You may need to select them again.'
            : 'An interrupted selection was not an image.';
      }
    }
  }

  Future<List<RecoveredScanFile>> pending() => storage.list();

  Future<Uint8List> read(String id) => storage.read(id);

  Future<void> discard(String id) => storage.discard(id);
}

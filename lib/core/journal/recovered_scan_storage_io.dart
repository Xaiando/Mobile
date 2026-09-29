import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../database/uuid.dart';
import 'journal_photo_store.dart';
import 'recovered_scan_file.dart';

bool get isAndroidRecoveryPlatform => Platform.isAndroid;

final _savedName = RegExp(
  r'^([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.(jpg|png)$',
);
const _partialSuffix = '.part';
final _pickerPathName = RegExp(
  r'^picker_cache_([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.json$',
);
const _maxPickerPaths = 32;
const _maxPickerPathBytes = 4096;
const _maxPickerRecordBytes = _maxPickerPathBytes + 128;
const _lostResultInProgressName = 'lost_result_in_progress_v1';

typedef _PickerPathRecord = ({File file, String path});

/// The only durable staging area for a photo returned after an Android
/// picker restart. Files are sanitized before entry and are never arbitrary
/// paths supplied by image_picker or a backup.
class RecoveredScanStorage {
  RecoveredScanStorage({this.rootPath, this.pickerCacheRootPath});

  // A pending() read can overlap startup staging in the same process.
  static final _activePartials = <String>{};
  static Future<void> _inventoryTail = Future<void>.value();

  /// Inject a private temporary root in tests. The production root is the
  /// application's support directory, not the OS-managed cache.
  final String? rootPath;

  /// Test override. Production accepts only files under app temporary storage.
  final String? pickerCacheRootPath;

  Future<T> _withInventoryLock<T>(Future<T> Function() task) async {
    final prior = _inventoryTail;
    final done = Completer<void>();
    _inventoryTail = done.future;
    await prior;
    try {
      return await task();
    } finally {
      done.complete();
    }
  }

  Future<String> _cacheRoot() async =>
      Directory(pickerCacheRootPath ?? (await getTemporaryDirectory()).path)
          .resolveSymbolicLinks();

  static bool _inside(String path, String root) {
    final actualPath = Platform.isWindows ? path.toLowerCase() : path;
    final actualRoot = Platform.isWindows ? root.toLowerCase() : root;
    final prefix = actualRoot.endsWith(Platform.pathSeparator)
        ? actualRoot
        : '$actualRoot${Platform.pathSeparator}';
    return actualPath.startsWith(prefix);
  }

  Future<String?> _canonicalCacheFile(String path) async {
    if (utf8.encode(path).length > _maxPickerPathBytes) {
      throw StateError('Picker cache path is too long to retain.');
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.link) {
      return null;
    }
    final canonical = await File(path).resolveSymbolicLinks();
    if (utf8.encode(canonical).length > _maxPickerPathBytes) {
      throw StateError('Picker cache path is too long to retain.');
    }
    if (!_inside(canonical, await _cacheRoot()) ||
        await FileSystemEntity.type(canonical, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    return canonical;
  }

  File _lostResultMarker(Directory directory) => File(
    '${directory.path}${Platform.pathSeparator}$_lostResultInProgressName',
  );

  /// The native picker result is consumed when retrieved. This flushed marker
  /// makes a crash before its paths are inventoried visible after restart.
  /// True means a prior retrieval may already have consumed its result.
  Future<bool> beginLostResult() => _withInventoryLock(() async {
    final directory = await _directory(create: true);
    final marker = _lostResultMarker(directory);
    final type = await FileSystemEntity.type(marker.path, followLinks: false);
    if (type == FileSystemEntityType.file) return true;
    if (type != FileSystemEntityType.notFound) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    await marker.writeAsString('1', flush: true);
    return false;
  });

  /// A null inventory result is safe only when the source is demonstrably
  /// absent. An inaccessible or existing outside-cache path remains unknown.
  Future<bool> pickerPathExists(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound;
    } on FileSystemException {
      return true;
    }
  }

  /// Called only after all returned app-cache paths are durable or removed.
  Future<void> completeLostResult() => _withInventoryLock(() async {
    final directory = await _directory();
    final marker = _lostResultMarker(directory);
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Interrupted picker result marker is missing.');
    }
    await marker.delete();
  });

  Future<String?> _readPickerPath(File file, String cacheRoot) async {
    if (await file.length() > _maxPickerRecordBytes) return null;
    try {
      final row = jsonDecode(await file.readAsString());
      if (row is! Map<String, dynamic> || row['schemaVersion'] != 1) {
        return null;
      }
      final path = row['path'];
      if (path is! String ||
          path.isEmpty ||
          utf8.encode(path).length > _maxPickerPathBytes ||
          !_inside(path, cacheRoot) ||
          path
              .split(RegExp(r'[\\/]'))
              .any((part) => part == '..' || part == '.')) {
        return null;
      }
      return path;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<List<_PickerPathRecord>> _pickerPathRecords(
    Directory directory,
  ) async {
    if (!await directory.exists()) return const [];
    String? cacheRoot;
    final records = <_PickerPathRecord>[];
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      final isPartial = name.endsWith(_partialSuffix);
      final savedName = isPartial
          ? name.substring(0, name.length - _partialSuffix.length)
          : name;
      if (!_pickerPathName.hasMatch(savedName)) continue;
      final root = cacheRoot ??= await _cacheRoot();
      if (entry is! File) {
        throw StateError(
          'Picker cache inventory contains a link or directory.',
        );
      }
      if (isPartial) {
        final path = await _readPickerPath(entry, root);
        if (path == null) {
          await entry.delete();
          continue;
        }
        final finalFile = File(
          entry.path.substring(0, entry.path.length - _partialSuffix.length),
        );
        if (await FileSystemEntity.type(finalFile.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await entry.delete();
          continue;
        }
        await entry.rename(finalFile.path);
        records.add((file: finalFile, path: path));
      } else {
        final path = await _readPickerPath(entry, root);
        if (path == null) {
          throw StateError('Picker cache inventory is unreadable.');
        }
        records.add((file: entry, path: path));
      }
      if (records.length > _maxPickerPaths) {
        throw StateError('Picker cache inventory is too large.');
      }
    }
    return records;
  }

  Future<Directory> _directory({bool create = false}) async {
    final path =
        rootPath ??
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}recovered_scans_v1';
    final directory = Directory(path);
    if (create) await directory.create(recursive: true);
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Recovered photo directory cannot be a link.');
    }
    return directory;
  }

  Future<List<RecoveredScanFile>> list() async {
    final directory = await _directory();
    if (!await directory.exists()) return const [];
    final recovered = <String, RecoveredScanFile>{};
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final match = _savedName.firstMatch(name);
      if (match == null) {
        if (name.endsWith(_partialSuffix) &&
            !_activePartials.contains(entry.path)) {
          final partialMatch = _savedName.firstMatch(
            name.substring(0, name.length - _partialSuffix.length),
          );
          if (partialMatch != null) {
            final restored = await _recoverPartial(entry, partialMatch);
            if (restored != null) recovered[restored.id] = restored;
          }
        }
        continue;
      }
      recovered[match.group(1)!] = RecoveredScanFile(
        id: match.group(1)!,
        path: entry.path,
        mimeType: match.group(2) == 'png' ? 'image/png' : 'image/jpeg',
      );
    }
    final files = recovered.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return files;
  }

  /// A killed process may leave a flushed image between write and rename.
  /// Promote only complete, sanitized photos; delete incomplete partials.
  Future<RecoveredScanFile?> _recoverPartial(
    File partial,
    RegExpMatch name,
  ) async {
    _activePartials.add(partial.path);
    try {
      return await _recoverInactivePartial(partial, name);
    } finally {
      _activePartials.remove(partial.path);
    }
  }

  Future<RecoveredScanFile?> _recoverInactivePartial(
    File partial,
    RegExpMatch name,
  ) async {
    final path = partial.path.substring(
      0,
      partial.path.length - _partialSuffix.length,
    );
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await partial.delete();
      return null;
    }
    final mimeType = name.group(2) == 'png' ? 'image/png' : 'image/jpeg';
    try {
      final length = await partial.length();
      if (length <= 0 || length > JournalPhotoStore.maxBytes) {
        throw const PhotoStoreException('Recovered photo is invalid.');
      }
      JournalPhotoStore.validateStoredPhoto(
        mimeType,
        await partial.readAsBytes(),
      );
    } on PhotoStoreException {
      await partial.delete();
      return null;
    }
    await partial.rename(path);
    return RecoveredScanFile(
      id: name.group(1)!,
      path: path,
      mimeType: mimeType,
    );
  }

  Future<RecoveredScanFile> stage(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > JournalPhotoStore.maxBytes) {
      throw const PhotoStoreException('Recovered photo is too large.');
    }
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    if (!isPng && !isJpeg) {
      throw const PhotoStoreException('Recovered photo is not JPEG or PNG.');
    }
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    JournalPhotoStore.validateStoredPhoto(mimeType, bytes);
    final directory = await _directory(create: true);
    final id = newUuid();
    final suffix = isPng ? '.png' : '.jpg';
    final path = '${directory.path}${Platform.pathSeparator}$id$suffix';
    final partial = File('$path$_partialSuffix');
    _activePartials.add(partial.path);
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(path);
    } catch (_) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {
        // Keep the staging failure; a later list can handle the partial.
      }
      rethrow;
    } finally {
      _activePartials.remove(partial.path);
    }
    return RecoveredScanFile(id: id, path: path, mimeType: mimeType);
  }

  Future<RecoveredScanFile> _byId(String id) async {
    if (!_savedName.hasMatch('$id.jpg')) {
      throw const FormatException('Invalid recovered photo ID.');
    }
    for (final file in await list()) {
      if (file.id == id) return file;
    }
    throw StateError('Recovered photo was not found.');
  }

  Future<Uint8List> read(String id) async {
    final file = await _byId(id);
    final length = await File(file.path).length();
    if (length <= 0 || length > JournalPhotoStore.maxBytes) {
      throw const PhotoStoreException('Recovered photo is invalid.');
    }
    final bytes = await File(file.path).readAsBytes();
    JournalPhotoStore.validateStoredPhoto(file.mimeType, bytes);
    return bytes;
  }

  Future<void> discard(String id) async {
    final file = await _byId(id);
    await File(file.path).delete();
  }

  /// Durably remember an app-cache picker copy before consuming it. Paths are
  /// inventory data only; this class never deletes the picker file itself.
  /// Missing, non-file, and outside-cache paths are not recorded.
  Future<String?> recordPickerCachePath(String path) async {
    final canonical = await _canonicalCacheFile(path);
    if (canonical == null) return null;
    return _withInventoryLock(() async {
      final directory = await _directory(create: true);
      final records = await _pickerPathRecords(directory);
      if (records.any((record) => record.path == canonical)) return canonical;
      if (records.length >= _maxPickerPaths) {
        throw StateError('Too many interrupted picker paths to retain.');
      }
      final id = newUuid();
      final saved = File(
        '${directory.path}${Platform.pathSeparator}picker_cache_$id.json',
      );
      final partial = File('${saved.path}$_partialSuffix');
      try {
        await partial.writeAsString(
          jsonEncode({'schemaVersion': 1, 'path': canonical}),
          flush: true,
        );
        await partial.rename(saved.path);
      } catch (_) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {
          // A later inventory read can handle the partial.
        }
        rethrow;
      }
      return canonical;
    });
  }

  /// App-cache paths awaiting verified removal by the guarded picker cleaner.
  Future<List<String>> pendingPickerCachePaths() => _withInventoryLock(
    () async {
      final directory = await _directory();
      if (await FileSystemEntity.type(
            _lostResultMarker(directory).path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('An interrupted picker result needs manual recovery.');
      }
      final paths = {
        for (final record in await _pickerPathRecords(directory)) record.path,
      }.toList()..sort();
      return paths;
    },
  );

  /// Forget inventory records only after the caller verifies cache cleanup.
  Future<void> forgetPickerCachePath(String canonicalPath) =>
      _withInventoryLock(() async {
        final directory = await _directory();
        for (final record in await _pickerPathRecords(directory)) {
          if (record.path == canonicalPath) await record.file.delete();
        }
      });

  /// Delete only direct children of our dedicated app-support directory.
  /// Never recursively traverse a path supplied by a picker or a backup.
  Future<void> clearAll() => _withInventoryLock(() async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    if (await FileSystemEntity.type(
          _lostResultMarker(directory).path,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File || entry is Link) {
        await entry.delete();
      } else {
        throw StateError('Unexpected nested recovered photo directory.');
      }
    }
    await directory.delete();
  });
}

/// Called by Erase All after the database erase succeeds.
Future<void> clearRecoveredScanStaging() => Platform.isAndroid
    ? RecoveredScanStorage().clearAll()
    : Future<void>.value();

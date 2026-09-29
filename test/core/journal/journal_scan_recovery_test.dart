import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/journal_scan_recovery.dart';
import 'package:sommelier/core/journal/recovered_scan_storage.dart';

class _FakePicker extends ImagePicker {
  _FakePicker(this.response);
  final LostDataResponse response;
  int calls = 0;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    calls++;
    return response;
  }
}

class _DeferredPicker extends ImagePicker {
  final response = Completer<LostDataResponse>();
  int calls = 0;

  @override
  Future<LostDataResponse> retrieveLostData() {
    calls++;
    return response.future;
  }
}

class _ThrowOncePicker extends ImagePicker {
  _ThrowOncePicker(this.response);
  final LostDataResponse response;
  int calls = 0;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    calls++;
    if (calls == 1) throw StateError('temporary picker failure');
    return response;
  }
}

class _FailingStorage extends RecoveredScanStorage {
  _FailingStorage(String rootPath, {super.pickerCacheRootPath})
    : super(rootPath: rootPath);

  @override
  Future<RecoveredScanFile> stage(Uint8List bytes) async =>
      throw StateError('disk full');
}

class _UninventoriableStorage extends RecoveredScanStorage {
  _UninventoriableStorage({
    required super.rootPath,
    required super.pickerCacheRootPath,
  });

  @override
  Future<String?> recordPickerCachePath(String path) async =>
      throw StateError('inventory write failed');
}

class _BeginFailsOnceStorage extends RecoveredScanStorage {
  _BeginFailsOnceStorage(String rootPath) : super(rootPath: rootPath);

  var failNextBegin = true;

  @override
  Future<bool> beginLostResult() async {
    if (failNextBegin) {
      failNextBegin = false;
      throw StateError('marker write failed');
    }
    return super.beginLostResult();
  }
}

Uint8List _png() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2)));

Future<void> _removeTestRoot(Directory root) async {
  if (!await root.exists()) return;
  final target = await root.resolveSymbolicLinks();
  final temporary = await Directory.systemTemp.resolveSymbolicLinks();
  final prefix = '$temporary${Platform.pathSeparator}recovered-scan-test-';
  if (!target.toLowerCase().startsWith(prefix.toLowerCase())) {
    throw StateError('Unexpected test cleanup path.');
  }
  await root.delete(recursive: true);
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recovered-scan-test-');
  });
  tearDown(() => _removeTestRoot(root));

  test(
    'startup saves every lost image durably and only then cleans cache',
    () async {
      final source = _png();
      final picker = _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [
            XFile.fromData(source, path: 'picker-cache-a.png'),
            XFile.fromData(source, path: 'picker-cache-b.png'),
          ],
        ),
      );
      final cleaned = <String>[];
      final storage = RecoveredScanStorage(rootPath: root.path);
      final recovery = JournalScanRecovery(
        picker: picker,
        storage: storage,
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          expect((await storage.list()).length, greaterThanOrEqualTo(1));
          cleaned.add(path);
          return true;
        },
      );

      await recovery.recoverAtStartup();
      await recovery.recoverAtStartup();
      expect(picker.calls, 1);
      final pending = await recovery.pending();
      expect(pending, hasLength(2));
      expect(cleaned, ['picker-cache-a.png', 'picker-cache-b.png']);
      for (final file in pending) {
        expect(file.path, startsWith(root.path));
        expect(
          await recovery.read(file.id),
          JournalPhotoStore.sanitize(source),
        );
      }

      final restarted = JournalScanRecovery(
        picker: _FakePicker(LostDataResponse.empty()),
        storage: RecoveredScanStorage(rootPath: root.path),
        androidRuntime: true,
      );
      expect(await restarted.pending(), hasLength(2));
      await restarted.recoverAtStartup();
      expect(await restarted.pending(), hasLength(2));
    },
  );

  test(
    'failed staging retains the picker copy and reports a warning',
    () async {
      final picker = _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [XFile.fromData(_png(), path: 'picker-cache.png')],
        ),
      );
      final cleaned = <String>[];
      final recovery = JournalScanRecovery(
        picker: picker,
        storage: _FailingStorage(root.path),
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          cleaned.add(path);
          return true;
        },
      );

      await recovery.recoverAtStartup();
      expect(cleaned, isEmpty);
      expect(recovery.warning, contains('could not be recovered'));
    },
  );

  test(
    'staged photo cleanup retries across restarts after its copy is dismissed',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final original = File('${cache.path}${Platform.pathSeparator}old.png');
      await original.writeAsBytes(_png());
      final canonicalOriginal = await original.resolveSymbolicLinks();
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      RecoveredScanStorage storage() => RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: original.path)],
          ),
        ),
        storage: storage(),
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await first.recoverAtStartup();
      expect(first.warning, contains('remains in temporary device storage'));
      final staged = await first.pending();
      expect(staged, hasLength(1));
      await first.discard(staged.single.id);
      expect(await first.pending(), isEmpty);
      expect(await original.exists(), isTrue);
      expect(await storage().pendingPickerCachePaths(), [canonicalOriginal]);

      final failedRetryPicker = _FakePicker(LostDataResponse.empty());
      final failedRetry = JournalScanRecovery(
        picker: failedRetryPicker,
        storage: storage(),
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await failedRetry.recoverAtStartup();
      expect(failedRetryPicker.calls, 1);
      expect(
        failedRetry.warning,
        contains('remains in temporary device storage'),
      );
      expect(await original.exists(), isTrue);
      expect(await storage().pendingPickerCachePaths(), [canonicalOriginal]);

      final successfulPicker = _FakePicker(LostDataResponse.empty());
      final successfulRetry = JournalScanRecovery(
        picker: successfulPicker,
        storage: storage(),
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          expect(successfulPicker.calls, 0);
          await File(path).delete();
          return true;
        },
      );
      await successfulRetry.recoverAtStartup();
      expect(successfulPicker.calls, 1);
      expect(successfulRetry.warning, isNull);
      expect(await original.exists(), isFalse);
      expect(await storage().pendingPickerCachePaths(), isEmpty);
      expect(await successfulRetry.pending(), isEmpty);
    },
  );

  test(
    'failed staging leaves its only picker copy outside startup retry',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final original = File('${cache.path}${Platform.pathSeparator}old.png');
      await original.writeAsBytes(_png());
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      final firstStorage = _FailingStorage(
        stageRoot,
        pickerCacheRootPath: cache.path,
      );
      var firstCleanupCalls = 0;
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: original.path)],
          ),
        ),
        storage: firstStorage,
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          firstCleanupCalls++;
          await File(path).delete();
          return true;
        },
      );
      await first.recoverAtStartup();
      expect(firstCleanupCalls, 0);
      expect(first.warning, contains('needs device cleanup'));
      expect(await first.pending(), isEmpty);
      expect(await original.exists(), isTrue);
      await expectLater(firstStorage.pendingPickerCachePaths(), throwsStateError);

      var cleanupCalls = 0;
      final restartedStorage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final restarted = JournalScanRecovery(
        picker: _FakePicker(LostDataResponse.empty()),
        storage: restartedStorage,
        androidRuntime: true,
        cleanupPickerFile: (_) async {
          cleanupCalls++;
          return true;
        },
      );
      await restarted.recoverAtStartup();
      expect(cleanupCalls, 0);
      expect(restarted.warning, contains('needs device cleanup'));
      expect(await original.exists(), isTrue);
      await expectLater(
        restartedStorage.pendingPickerCachePaths(),
        throwsStateError,
      );
    },
  );

  test('Erase All consumes an old picker result without staging it', () async {
    final picker = _FakePicker(
      LostDataResponse(
        type: RetrieveType.image,
        files: [XFile.fromData(_png(), path: 'old-picker-cache.png')],
      ),
    );
    final cleaned = <String>[];
    final recovery = JournalScanRecovery(
      picker: picker,
      storage: RecoveredScanStorage(rootPath: root.path),
      androidRuntime: true,
      cleanupPickerFile: (path) async {
        cleaned.add(path);
        return true;
      },
    );
    await recovery.discardLostAfterErase();
    await recovery.recoverAtStartup();
    expect(picker.calls, 1);
    expect(cleaned, ['old-picker-cache.png']);
    expect(await recovery.pending(), isEmpty);
  });

  test('Erase All waits for an in-flight stage before clearing it', () async {
    final picker = _DeferredPicker();
    final storage = RecoveredScanStorage(rootPath: root.path);
    final recovery = JournalScanRecovery(
      picker: picker,
      storage: storage,
      androidRuntime: true,
      cleanupPickerFile: (_) async => true,
    );
    final startup = recovery.recoverAtStartup();
    final erase = () async {
      await recovery.discardLostAfterErase();
      await storage.clearAll();
    }();
    picker.response.complete(
      LostDataResponse(
        type: RetrieveType.image,
        files: [XFile.fromData(_png(), path: 'old-picker-cache.png')],
      ),
    );
    await Future.wait([startup, erase]);
    expect(picker.calls, 1);
    expect(await storage.list(), isEmpty);
  });

  test(
    'Erase All keeps a prior marker after a nonempty native retry',
    () async {
      final picker = _ThrowOncePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [XFile.fromData(_png(), path: 'old-picker-cache.png')],
        ),
      );
      final storage = RecoveredScanStorage(rootPath: root.path);
      final recovery = JournalScanRecovery(
        picker: picker,
        storage: storage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => true,
      );
      await recovery.recoverAtStartup();
      expect(recovery.warning, contains('could not be checked'));
      await expectLater(recovery.discardLostAfterErase(), throwsStateError);
      await expectLater(storage.clearAll(), throwsStateError);
      expect(picker.calls, 2);
    },
  );

  test(
    'Erase All retries native retrieval after a failed marker write',
    () async {
      final picker = _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [XFile.fromData(_png(), path: 'old-picker-cache.png')],
        ),
      );
      final storage = _BeginFailsOnceStorage(root.path);
      final recovery = JournalScanRecovery(
        picker: picker,
        storage: storage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => true,
      );
      await recovery.recoverAtStartup();
      expect(picker.calls, 0);
      await recovery.discardLostAfterErase();
      expect(picker.calls, 1);
      expect(await storage.pendingPickerCachePaths(), isEmpty);
    },
  );

  test(
    'an unrecorded picker path cannot be forgotten after a restart',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final source = File('${cache.path}${Platform.pathSeparator}old.png');
      await source.writeAsBytes(_png());
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      final firstStorage = _UninventoriableStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: source.path)],
          ),
        ),
        storage: firstStorage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await expectLater(first.discardLostAfterErase(), throwsStateError);
      await expectLater(
        firstStorage.pendingPickerCachePaths(),
        throwsStateError,
      );
      expect(await source.exists(), isTrue);

      final restartedPicker = _FakePicker(LostDataResponse.empty());
      final restartedStorage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final restarted = JournalScanRecovery(
        picker: restartedPicker,
        storage: restartedStorage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => true,
      );
      await expectLater(restarted.discardLostAfterErase(), throwsStateError);
      expect(restartedPicker.calls, 1);
      await expectLater(restartedStorage.clearAll(), throwsStateError);
      expect(await source.exists(), isTrue);
    },
  );

  test(
    'a later picker result cannot clear a marker for an earlier lost photo',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final sourceA = File('${cache.path}${Platform.pathSeparator}old-a.png');
      final sourceB = File('${cache.path}${Platform.pathSeparator}new-b.png');
      await sourceA.writeAsBytes(_png());
      await sourceB.writeAsBytes(_png());
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: sourceA.path)],
          ),
        ),
        storage: _UninventoriableStorage(
          rootPath: stageRoot,
          pickerCacheRootPath: cache.path,
        ),
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await expectLater(first.discardLostAfterErase(), throwsStateError);
      expect(await sourceA.exists(), isTrue);

      final restartedStorage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final pickerB = _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [XFile.fromData(_png(), path: sourceB.path)],
        ),
      );
      final restarted = JournalScanRecovery(
        picker: pickerB,
        storage: restartedStorage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await expectLater(restarted.discardLostAfterErase(), throwsStateError);
      expect(pickerB.calls, 1);
      expect(await sourceA.exists(), isTrue);
      expect(await sourceB.exists(), isTrue);
      expect(await restartedStorage.beginLostResult(), isTrue);
      await expectLater(restartedStorage.clearAll(), throwsStateError);
    },
  );

  test(
    'startup can stage a later photo without clearing an older marker',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final sourceA = File('${cache.path}${Platform.pathSeparator}old-a.png');
      final sourceB = File('${cache.path}${Platform.pathSeparator}new-b.png');
      await sourceA.writeAsBytes(_png());
      await sourceB.writeAsBytes(_png());
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: sourceA.path)],
          ),
        ),
        storage: _UninventoriableStorage(
          rootPath: stageRoot,
          pickerCacheRootPath: cache.path,
        ),
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await expectLater(first.discardLostAfterErase(), throwsStateError);

      final restartedStorage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final restarted = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: sourceB.path)],
          ),
        ),
        storage: restartedStorage,
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          if (path != sourceB.path) return false;
          await sourceB.delete();
          return true;
        },
      );
      await restarted.recoverAtStartup();
      expect(await restarted.pending(), hasLength(1));
      expect(await sourceB.exists(), isFalse);
      expect(await sourceA.exists(), isTrue);
      expect(restarted.warning, contains('needs device cleanup'));
      await expectLater(restartedStorage.clearAll(), throwsStateError);
    },
  );

  test('Erase All keeps an existing outside-cache path unresolved', () async {
    final cache = await Directory('${root.path}${Platform.pathSeparator}cache')
        .create();
    final outside = File('${root.path}${Platform.pathSeparator}external.png');
    await outside.writeAsBytes(_png());
    final storage = RecoveredScanStorage(
      rootPath: '${root.path}${Platform.pathSeparator}recovered_scans_v1',
      pickerCacheRootPath: cache.path,
    );
    final recovery = JournalScanRecovery(
      picker: _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [XFile.fromData(_png(), path: outside.path)],
        ),
      ),
      storage: storage,
      androidRuntime: true,
      cleanupPickerFile: (_) async => false,
    );
    await expectLater(recovery.discardLostAfterErase(), throwsStateError);
    await expectLater(storage.pendingPickerCachePaths(), throwsStateError);
    expect(await outside.exists(), isTrue);
  });

  test(
    'failed cache deletion stays in inventory for a later restart',
    () async {
      final cache = await Directory(
        '${root.path}${Platform.pathSeparator}cache',
      ).create();
      final original = File('${cache.path}${Platform.pathSeparator}old.png');
      await original.writeAsBytes(_png());
      final stageRoot =
          '${root.path}${Platform.pathSeparator}recovered_scans_v1';
      final storage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final first = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_png(), path: original.path)],
          ),
        ),
        storage: storage,
        androidRuntime: true,
        cleanupPickerFile: (_) async => false,
      );
      await expectLater(first.discardLostAfterErase(), throwsStateError);
      expect(await storage.pendingPickerCachePaths(), hasLength(1));
      expect(await original.exists(), isTrue);

      final restartedStorage = RecoveredScanStorage(
        rootPath: stageRoot,
        pickerCacheRootPath: cache.path,
      );
      final restarted = JournalScanRecovery(
        picker: _FakePicker(LostDataResponse.empty()),
        storage: restartedStorage,
        androidRuntime: true,
        cleanupPickerFile: (path) async {
          await File(path).delete();
          return true;
        },
      );
      await restarted.discardLostAfterErase();
      await restartedStorage.clearAll();
      expect(await original.exists(), isFalse);
      expect(await restartedStorage.pendingPickerCachePaths(), isEmpty);
    },
  );

  test(
    'lost picker exception is surfaced without clearing saved stages',
    () async {
      final storage = RecoveredScanStorage(rootPath: root.path);
      await storage.stage(JournalPhotoStore.sanitize(_png()));
      final recovery = JournalScanRecovery(
        picker: _FakePicker(
          LostDataResponse(exception: PlatformException(code: 'picker_failed')),
        ),
        storage: storage,
        androidRuntime: true,
      );

      await recovery.recoverAtStartup();
      expect(recovery.warning, contains('did not return a photo'));
      expect(await recovery.pending(), hasLength(1));
    },
  );

  test('oversized lost image keeps an earlier recovered stage', () async {
    final source = _png();
    final cleaned = <String>[];
    final recovery = JournalScanRecovery(
      picker: _FakePicker(
        LostDataResponse(
          type: RetrieveType.image,
          files: [
            XFile.fromData(source, path: 'small.png'),
            XFile.fromData(
              Uint8List(JournalPhotoStore.maxImportBytes + 1),
              path: 'too-large.png',
            ),
          ],
        ),
      ),
      storage: RecoveredScanStorage(rootPath: root.path),
      androidRuntime: true,
      cleanupPickerFile: (path) async {
        cleaned.add(path);
        return true;
      },
    );

    await recovery.recoverAtStartup();
    expect(recovery.warning, contains('could not be recovered'));
    expect(cleaned, ['small.png']);
    final pending = await recovery.pending();
    expect(pending, hasLength(1));
    expect(
      await recovery.read(pending.single.id),
      JournalPhotoStore.sanitize(source),
    );
  });

  test(
    'non-Android startup does not call the Android-only picker API',
    () async {
      final picker = _FakePicker(LostDataResponse.empty());
      final recovery = JournalScanRecovery(
        picker: picker,
        storage: RecoveredScanStorage(rootPath: root.path),
        androidRuntime: false,
      );
      await recovery.recoverAtStartup();
      expect(picker.calls, 0);
    },
  );

  test(
    'global Erase All hook is safe where Android staging is unavailable',
    () async {
      if (!Platform.isAndroid) await clearRecoveredScanStaging();
    },
  );

  test(
    'dismissal and Erase All storage cleanup cannot delete a sibling file',
    () async {
      final storage = RecoveredScanStorage(
        rootPath: '${root.path}${Platform.pathSeparator}recovered_scans_v1',
      );
      final sibling = File('${root.path}${Platform.pathSeparator}keep.png');
      await sibling.writeAsBytes(_png());
      final first = await storage.stage(JournalPhotoStore.sanitize(_png()));
      final second = await storage.stage(JournalPhotoStore.sanitize(_png()));

      await storage.discard(first.id);
      expect(await storage.list(), hasLength(1));
      await expectLater(storage.discard('../keep'), throwsFormatException);
      await storage.clearAll();
      expect(await storage.list(), isEmpty);
      expect(await sibling.exists(), isTrue);
      expect(await File(second.path).exists(), isFalse);
    },
  );

  test('a complete abandoned partial is promoted for recovery', () async {
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}recovered_scans_v1',
    ).create();
    const id = '00000000-0000-4000-8000-000000000001';
    final partial = File(
      '${directory.path}${Platform.pathSeparator}$id.png.part',
    );
    final bytes = JournalPhotoStore.sanitize(_png());
    await partial.writeAsBytes(bytes, flush: true);
    final storage = RecoveredScanStorage(rootPath: directory.path);

    final pending = await storage.list();
    expect(pending, hasLength(1));
    expect(pending.single.id, id);
    expect(await storage.read(id), bytes);
    expect(await partial.exists(), isFalse);
    expect(await File(pending.single.path).exists(), isTrue);
  });

  test('invalid partials are removed without touching other files', () async {
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}recovered_scans_v1',
    ).create();
    final invalid = File(
      '${directory.path}${Platform.pathSeparator}'
      '00000000-0000-4000-8000-000000000001.png.part',
    );
    final unrelated = File(
      '${directory.path}${Platform.pathSeparator}keep.part',
    );
    await invalid.writeAsBytes([1, 2, 3], flush: true);
    await unrelated.writeAsBytes([4, 5, 6], flush: true);
    final storage = RecoveredScanStorage(rootPath: directory.path);

    expect(await storage.list(), isEmpty);
    expect(await invalid.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('a partial never replaces an existing recovered photo', () async {
    final storage = RecoveredScanStorage(rootPath: root.path);
    final original = JournalPhotoStore.sanitize(_png());
    final saved = await storage.stage(original);
    final duplicate = File('${saved.path}.part');
    await duplicate.writeAsBytes(original, flush: true);

    expect(await storage.list(), hasLength(1));
    expect(await storage.read(saved.id), original);
    expect(await duplicate.exists(), isFalse);
  });
}

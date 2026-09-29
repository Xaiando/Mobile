import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/journal/recovered_scan_storage.dart';

Future<void> _removeTestRoot(Directory root) async {
  if (!await root.exists()) return;
  final target = await root.resolveSymbolicLinks();
  final temporary = await Directory.systemTemp.resolveSymbolicLinks();
  final prefix = '$temporary${Platform.pathSeparator}picker-inventory-test-';
  if (!target.toLowerCase().startsWith(prefix.toLowerCase())) {
    throw StateError('Unexpected test cleanup path.');
  }
  await root.delete(recursive: true);
}

void main() {
  late Directory root;
  late Directory cache;
  late RecoveredScanStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picker-inventory-test-');
    cache = await Directory('${root.path}${Platform.pathSeparator}cache')
        .create();
    storage = RecoveredScanStorage(
      rootPath: '${root.path}${Platform.pathSeparator}recovered_scans_v1',
      pickerCacheRootPath: cache.path,
    );
  });
  tearDown(() => _removeTestRoot(root));

  test(
    'picker path inventory survives restart and never deletes cache files',
    () async {
      final inside = File('${cache.path}${Platform.pathSeparator}picker.png');
      await inside.writeAsBytes([1, 2, 3]);
      final outside = File('${root.path}${Platform.pathSeparator}outside.png');
      await outside.writeAsBytes([4, 5, 6]);
      final canonical = await inside.resolveSymbolicLinks();

      expect(await storage.recordPickerCachePath(inside.path), canonical);
      expect(await storage.recordPickerCachePath(inside.path), canonical);
      expect(await storage.recordPickerCachePath(outside.path), isNull);
      expect(await storage.pendingPickerCachePaths(), [canonical]);

      final restarted = RecoveredScanStorage(
        rootPath: '${root.path}${Platform.pathSeparator}recovered_scans_v1',
        pickerCacheRootPath: cache.path,
      );
      expect(await restarted.pendingPickerCachePaths(), [canonical]);
      await restarted.forgetPickerCachePath(canonical);
      expect(await restarted.pendingPickerCachePaths(), isEmpty);
      expect(await inside.exists(), isTrue);
      expect(await outside.exists(), isTrue);

      await restarted.recordPickerCachePath(inside.path);
      await restarted.clearAll();
      expect(await restarted.pendingPickerCachePaths(), isEmpty);
      expect(await inside.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    },
  );

  test('a complete interrupted inventory write is promoted', () async {
    final inside = File('${cache.path}${Platform.pathSeparator}picker.png');
    await inside.writeAsBytes([1]);
    final canonical = await inside.resolveSymbolicLinks();
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}recovered_scans_v1',
    ).create();
    const id = '00000000-0000-4000-8000-000000000001';
    final partial = File(
      '${directory.path}${Platform.pathSeparator}picker_cache_$id.json.part',
    );
    await partial.writeAsString(
      jsonEncode({'schemaVersion': 1, 'path': canonical}),
      flush: true,
    );

    expect(await storage.pendingPickerCachePaths(), [canonical]);
    expect(await partial.exists(), isFalse);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}picker_cache_$id.json',
      ).exists(),
      isTrue,
    );
  });

  test('a tampered inventory cannot expose a path outside app cache', () async {
    final outside = File('${root.path}${Platform.pathSeparator}outside.png');
    await outside.writeAsBytes([1]);
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}recovered_scans_v1',
    ).create();
    final record = File(
      '${directory.path}${Platform.pathSeparator}'
      'picker_cache_00000000-0000-4000-8000-000000000001.json',
    );
    await record.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'path': await outside.resolveSymbolicLinks(),
      }),
      flush: true,
    );

    await expectLater(storage.pendingPickerCachePaths(), throwsStateError);
    expect(await outside.exists(), isTrue);
  });

  test('inventory is bounded before another picker path is accepted', () async {
    for (var i = 0; i < 32; i++) {
      final file = File('${cache.path}${Platform.pathSeparator}$i.png');
      await file.writeAsBytes([i]);
      expect(await storage.recordPickerCachePath(file.path), isNotNull);
    }
    final extra = File('${cache.path}${Platform.pathSeparator}extra.png');
    await extra.writeAsBytes([33]);
    await expectLater(
      storage.recordPickerCachePath(extra.path),
      throwsStateError,
    );
    expect(await storage.pendingPickerCachePaths(), hasLength(32));
  });
}

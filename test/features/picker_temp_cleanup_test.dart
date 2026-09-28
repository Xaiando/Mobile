import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/features/cellar/picker_temp_cleanup_io.dart';

void main() {
  late Directory sandbox;
  late Directory appTemp;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('sommelier-picker-test-');
    appTemp = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app-cache',
    ).create();
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test('removes a picker copy under app temporary storage after use', () async {
    // Android's gallery picker places its returned file in a UUID child.
    final pickerDirectory = await Directory(
      '${appTemp.path}${Platform.pathSeparator}picker-uuid',
    ).create();
    final photo = File(
      '${pickerDirectory.path}${Platform.pathSeparator}label.jpg',
    );
    await photo.writeAsString('temporary photo');

    final result = await withPickedTemporaryPhoto(photo.path, () async {
      expect(await photo.exists(), isTrue);
      return 'recognized';
    }, temporaryDirectoryPath: appTemp.path);

    expect(result, 'recognized');
    expect(await photo.exists(), isFalse);
  });

  test('removes a picker copy when processing throws', () async {
    final photo = File('${appTemp.path}${Platform.pathSeparator}label.jpg');
    await photo.writeAsString('temporary photo');

    await expectLater(
      withPickedTemporaryPhoto<void>(
        photo.path,
        () async => throw const FormatException('bad image'),
        temporaryDirectoryPath: appTemp.path,
      ),
      throwsFormatException,
    );
    expect(await photo.exists(), isFalse);
  });

  test('leaves a user source and a sibling directory untouched', () async {
    final source = File('${sandbox.path}${Platform.pathSeparator}source.jpg');
    final sibling = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app-cache-other',
    ).create();
    final siblingPhoto = File(
      '${sibling.path}${Platform.pathSeparator}other.jpg',
    );
    await source.writeAsString('user source');
    await siblingPhoto.writeAsString('other source');

    expect(
      await removePickedTemporaryPhoto(
        source.path,
        temporaryDirectoryPath: appTemp.path,
      ),
      isFalse,
    );
    expect(
      await removePickedTemporaryPhoto(
        siblingPhoto.path,
        temporaryDirectoryPath: appTemp.path,
      ),
      isFalse,
    );
    expect(await source.readAsString(), 'user source');
    expect(await siblingPhoto.readAsString(), 'other source');
  });

  test('removes an iOS picker copy only inside the app container', () async {
    final container = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app-container',
    ).create();
    final documents = await Directory(
      '${container.path}${Platform.pathSeparator}Documents',
    ).create();
    final pickerTemp = await Directory(
      '${container.path}${Platform.pathSeparator}tmp',
    ).create();
    final picked = File('${pickerTemp.path}${Platform.pathSeparator}label.jpg');
    await picked.writeAsString('picker copy');

    expect(
      await removePickedTemporaryPhoto(
        picked.path,
        temporaryDirectoryPath: appTemp.path,
        iosPickerTemporaryDirectoryPath: pickerTemp.path,
        applicationDocumentsDirectoryPath: documents.path,
      ),
      isTrue,
    );
    expect(await picked.exists(), isFalse);

    final outside = File('${sandbox.path}${Platform.pathSeparator}source.jpg');
    await outside.writeAsString('user source');
    expect(
      await removePickedTemporaryPhoto(
        outside.path,
        temporaryDirectoryPath: appTemp.path,
        iosPickerTemporaryDirectoryPath: pickerTemp.path,
        applicationDocumentsDirectoryPath: documents.path,
      ),
      isFalse,
    );
    expect(await outside.readAsString(), 'user source');
  });

  test('rejects a picker root outside the app container', () async {
    final container = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app-container',
    ).create();
    final documents = await Directory(
      '${container.path}${Platform.pathSeparator}Documents',
    ).create();
    final globalTemp = await Directory(
      '${sandbox.path}${Platform.pathSeparator}global-temp',
    ).create();
    final unrelated = File(
      '${globalTemp.path}${Platform.pathSeparator}unrelated.jpg',
    );
    await unrelated.writeAsString('unrelated');

    expect(
      await removePickedTemporaryPhoto(
        unrelated.path,
        temporaryDirectoryPath: appTemp.path,
        iosPickerTemporaryDirectoryPath: globalTemp.path,
        applicationDocumentsDirectoryPath: documents.path,
      ),
      isFalse,
    );
    expect(await unrelated.readAsString(), 'unrelated');
  });
}

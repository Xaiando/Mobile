import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/storage_durability.dart';

void main() {
  test("maps Drift's web storage implementations", () {
    const expected = {
      'opfsShared': StorageDurability.persistent,
      'opfsLocks': StorageDurability.persistent,
      'sharedIndexedDb': StorageDurability.persistent,
      'unsafeIndexedDb': StorageDurability.singleTabOnly,
      'inMemory': StorageDurability.memoryOnly,
    };
    expected.forEach((name, durability) {
      expect(
        StorageDurability.fromWebImplementation(name),
        durability,
        reason: name,
      );
    });
  });

  test('a report is persistent until the web tells otherwise', () {
    expect(StorageReport().durability, StorageDurability.persistent);
  });
}

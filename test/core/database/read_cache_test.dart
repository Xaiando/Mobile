import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/read_cache.dart';

void main() {
  group('ReadCache', () {
    test('reads each key once', () async {
      final cache = ReadCache();
      var reads = 0;
      Future<int> read() async => ++reads;

      expect(await cache.of('a', read), 1);
      expect(await cache.of('a', read), 1, reason: 'remembered');
      expect(await cache.of('b', read), 2, reason: 'another key');
      expect(await cache.of('a', read), 1);
      expect(reads, 2);
      expect(cache.length, 2);
    });

    test('keys are compared by value, so a record names its inputs', () async {
      final cache = ReadCache();
      var reads = 0;
      Future<String> read() async => 'read ${++reads}';

      expect(
        await cache.of(('ancestors', 'n_chablis', '2026-10-02'), read),
        'read 1',
      );
      expect(
        await cache.of(('ancestors', 'n_chablis', '2026-10-02'), read),
        'read 1',
      );
      expect(
        await cache.of(('ancestors', 'n_chablis', '2026-10-03'), read),
        'read 2',
        reason: 'another date is another question',
      );
      expect(await cache.of(('ancestors', 'n_chablis', null), read), 'read 3');
      expect(await cache.of(('ancestors', 'n_chablis', null), read), 'read 3');
    });

    test('remembers an empty answer', () async {
      final cache = ReadCache();
      var reads = 0;
      Future<String?> read() async {
        reads++;
        return null;
      }

      expect(await cache.of('absent', read), isNull);
      expect(await cache.of('absent', read), isNull);
      expect(reads, 1);
    });

    test('does not remember a failed read', () async {
      final cache = ReadCache();
      var reads = 0;
      Future<int> read() async {
        if (++reads == 1) throw StateError('database busy');
        return reads;
      }

      await expectLater(cache.of('k', read), throwsStateError);
      expect(await cache.of('k', read), 2, reason: 'the next call reads again');
      expect(await cache.of('k', read), 2);
    });

    test('a pass-through cache remembers nothing', () async {
      final cache = ReadCache.passThrough();
      var reads = 0;
      Future<int> read() async => ++reads;

      expect(await cache.of('a', read), 1);
      expect(await cache.of('a', read), 2);
      expect(cache.length, 0);
    });
  });
}

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/time/utc_clock.dart';

void main() {
  test('utcNow returns UTC truncated to whole milliseconds', () {
    final now = utcNow(
      Clock.fixed(DateTime.utc(2026, 1, 2, 3, 4, 5, 678, 901)),
    );
    expect(now.isUtc, isTrue);
    expect(now, DateTime.utc(2026, 1, 2, 3, 4, 5, 678));
    expect(now.toIso8601String(), '2026-01-02T03:04:05.678Z');
  });

  test('utcNow converts local time to UTC', () {
    final local = DateTime(2026, 1, 2, 3, 4, 5);
    expect(utcNow(Clock.fixed(local)), local.toUtc());
  });

  test('utcNow follows a zone clock set with withClock', () {
    final fixed = DateTime.utc(2030, 6, 1);
    expect(withClock(Clock.fixed(fixed), utcNow), fixed);
  });
}

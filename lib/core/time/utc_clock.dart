import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The clock the app reads time from. Tests override it with a fixed clock.
final clockProvider = Provider<Clock>((ref) => const Clock());

/// The current time as a UTC instant truncated to whole milliseconds.
///
/// Uses [source] when given, otherwise the zone's `clock` from package:clock,
/// so tests can also fix time with `withClock`.
DateTime utcNow([Clock? source]) => toStorageInstant((source ?? clock).now());

/// Converts [instant] to the form the database stores: UTC, whole milliseconds.
///
/// The schema accepts timestamps only as `YYYY-MM-DDTHH:MM:SS.sssZ`. Native
/// Dart clocks carry microseconds and web clocks do not, so truncating keeps
/// both platforms identical and text order equal to time order.
DateTime toStorageInstant(DateTime instant) =>
    DateTime.fromMillisecondsSinceEpoch(
      instant.millisecondsSinceEpoch,
      isUtc: true,
    );

import 'dart:math';

/// A random (version 4) UUID in lower case, the form the schema accepts for
/// rows the user creates.
///
/// Uses a cryptographically secure generator unless [random] is given, so
/// tests can make IDs reproducible.
String newUuid([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) source.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

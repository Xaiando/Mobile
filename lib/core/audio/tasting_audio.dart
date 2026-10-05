import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

/// Portable, versioned attachments kept in the existing backed-up user store.
/// No filesystem paths or browser blob URLs are persisted.
class TastingAudio {
  TastingAudio.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      sessionId = row['sessionId'] as String,
      title = row['title'] as String,
      mimeType = row['mimeType'] as String,
      durationMs = row['durationMs'] as int,
      byteLength = row['byteLength'] as int,
      digest = row['sha256'] as String,
      createdAt = DateTime.parse(row['createdAt'] as String) {
    if (row['schemaVersion'] != 1 ||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) ||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(sessionId) ||
        title.trim().isEmpty ||
        title.length > 120 ||
        !extensions.containsKey(mimeType) ||
        durationMs < 1 ||
        durationMs > 7200000 ||
        byteLength < 12 ||
        byteLength > TastingAudioStore.maxRecordingBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        !createdAt.isUtc) {
      throw const FormatException('Invalid audio attachment.');
    }
  }

  final String id, sessionId, title, mimeType, digest;
  final int durationMs, byteLength;
  final DateTime createdAt;
  static const extensions = {
    'audio/mp4': 'm4a',
    'audio/webm': 'webm',
    'audio/ogg': 'ogg',
    'audio/wav': 'wav',
  };
  String get extension => extensions[mimeType]!;
  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'sessionId': sessionId,
    'title': title,
    'mimeType': mimeType,
    'durationMs': durationMs,
    'byteLength': byteLength,
    'sha256': digest,
    'createdAt': createdAt.toIso8601String(),
  };
}

class TastingAudioStore {
  TastingAudioStore(this.db, {Clock? clock}) : clock = clock ?? const Clock();
  final AppDatabase db;
  final Clock clock;
  static const metaPrefix = 'tasting_audio_meta_v1_';
  static const dataPrefix = 'tasting_audio_data_v1_';
  static const maxRecordingBytes = 32 * 1024 * 1024;
  static const maxTotalBytes = 48 * 1024 * 1024;
  static String metaKey(String id) => '$metaPrefix${id.replaceAll('-', '_')}';
  static String dataKey(String id) => '$dataPrefix${id.replaceAll('-', '_')}';

  static bool hasContainer(String mime, List<int> bytes) {
    if (bytes.length < 12) return false;
    String at(int from, int to) =>
        ascii.decode(bytes.sublist(from, to), allowInvalid: true);
    return switch (mime) {
      'audio/mp4' => at(4, 8) == 'ftyp',
      'audio/webm' =>
        bytes[0] == 0x1a &&
            bytes[1] == 0x45 &&
            bytes[2] == 0xdf &&
            bytes[3] == 0xa3,
      'audio/ogg' => at(0, 4) == 'OggS',
      'audio/wav' => at(0, 4) == 'RIFF' && at(8, 12) == 'WAVE',
      _ => false,
    };
  }

  static TastingAudio parse(String key, String value) {
    final audio = TastingAudio.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
    if (metaKey(audio.id) != key) {
      throw const FormatException('Audio key mismatch.');
    }
    return audio;
  }

  /// Import preflight is atomic: refuse malformed or orphaned attachments.
  static void validateBackup(
    Map<String, String> settings,
    Set<String> sessionIds,
  ) {
    var total = 0;
    final expected = <String>{};
    for (final entry in settings.entries) {
      if (!entry.key.startsWith(metaPrefix)) continue;
      final audio = parse(entry.key, entry.value);
      if (!sessionIds.contains(audio.sessionId)) {
        throw const FormatException('Audio tasting missing.');
      }
      total += audio.byteLength;
      if (total > maxTotalBytes) {
        throw const FormatException('Audio storage exceeds 48 MiB.');
      }
      final key = dataKey(audio.id);
      expected.add(key);
      final encoded = settings[key];
      if (encoded == null ||
          encoded.length > ((maxRecordingBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Audio data missing or too large.');
      }
      validateBytes(audio, base64Decode(encoded));
    }
    if (settings.keys.any(
      (key) => key.startsWith(dataPrefix) && !expected.contains(key),
    )) {
      throw const FormatException('Orphaned audio data.');
    }
  }

  static void validateBytes(TastingAudio audio, Uint8List bytes) {
    if (bytes.length != audio.byteLength ||
        !hasContainer(audio.mimeType, bytes) ||
        sha256.convert(bytes).toString() != audio.digest) {
      throw const FormatException('The recording is damaged.');
    }
  }

  Stream<List<TastingAudio>> watch(String sessionId) =>
      (db.select(
        db.userSettings,
      )..where((s) => s.name.like('$metaPrefix%'))).watch().map((rows) {
        final all = rows
            .map((r) => parse(r.name, r.value))
            .where((r) => r.sessionId == sessionId)
            .toList();
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return all;
      });

  Future<TastingAudio> save({
    required String sessionId,
    required String title,
    required String mimeType,
    required int durationMs,
    required Uint8List bytes,
  }) => db.transaction(() async {
    if (bytes.length > maxRecordingBytes) {
      throw StateError(
        'The recording exceeds 32 MiB. Download it before discarding it.',
      );
    }
    final exists = await (db.select(
      db.tastingSessions,
    )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
    if (exists == null) throw StateError('This tasting no longer exists.');
    final metas = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$metaPrefix%'))).get();
    final total = metas.fold<int>(
      0,
      (sum, r) => sum + parse(r.name, r.value).byteLength,
    );
    if (total + bytes.length > maxTotalBytes) {
      throw StateError(
        'Audio storage is full (48 MiB). Download and remove older recordings, then retry saving.',
      );
    }
    final audio = TastingAudio.fromJson({
      'schemaVersion': 1,
      'id': newUuid(),
      'sessionId': sessionId,
      'title': title.trim(),
      'mimeType': mimeType,
      'durationMs': durationMs,
      'byteLength': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'createdAt': utcNow(clock).toIso8601String(),
    });
    validateBytes(audio, bytes);
    for (final entry in {
      metaKey(audio.id): jsonEncode(audio.toJson()),
      dataKey(audio.id): base64Encode(bytes),
    }.entries) {
      await db
          .into(db.userSettings)
          .insert(
            UserSettingsCompanion.insert(
              name: entry.key,
              value: entry.value,
              updatedAt: utcNow(clock),
            ),
          );
    }
    return audio;
  });

  Future<Uint8List> read(TastingAudio audio) async {
    final row = await (db.select(
      db.userSettings,
    )..where((s) => s.name.equals(dataKey(audio.id)))).getSingle();
    final bytes = base64Decode(row.value);
    validateBytes(audio, bytes);
    return bytes;
  }

  Future<void> delete(TastingAudio audio) => db.transaction(() async {
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.isIn([metaKey(audio.id), dataKey(audio.id)]))).go();
  });

  Future<void> deleteSession(String sessionId) => db.transaction(() async {
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$metaPrefix%'))).get();
    for (final row in rows) {
      final audio = parse(row.name, row.value);
      if (audio.sessionId == sessionId) await delete(audio);
    }
  });
}

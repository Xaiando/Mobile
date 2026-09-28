import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:image/image.dart' as image;

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

enum PhotoKind { label, glass }

/// Metadata only. Photo bytes are loaded only when [JournalPhotoStore.read]
/// is called, so a cellar list cannot accidentally read every image.
class JournalPhoto {
  const JournalPhoto({
    required this.key,
    required this.entryId,
    required this.kind,
    required this.mimeType,
    required this.createdAt,
  });

  final String key;
  final String entryId;
  final PhotoKind kind;
  final String mimeType;
  final DateTime createdAt;
}

class PhotoStoreException implements Exception {
  const PhotoStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Private, device-local label and glass photos for journal entries.
///
/// The opaque key names a SQLite BLOB, never a file path. [put] removes all
/// EXIF, ICC and text metadata by decoding and re-encoding a still image
/// before it writes anything. A replacement keeps the same key, and deletion
/// of a journal entry cascades to both photos in the database.
class JournalPhotoStore {
  JournalPhotoStore(this.db, {Clock? clock, this.random})
    : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;
  final Random? random;

  static const maxBytes = 8 * 1024 * 1024;
  static const maxImportBytes = 24 * 1024 * 1024;
  static const maxDimension = 6000;
  static const maxPixels = 20 * 1000 * 1000;
  static const maxImportPixels = 24 * 1000 * 1000;
  static const maxStoredDimension = 3000;

  /// Prepares a picked image before a journal draft is saved. The returned
  /// bytes have upright pixels and no EXIF, ICC profile or text metadata.
  /// Desktop pickers may ignore resize requests, so a bounded larger input
  /// is reduced here before the 8 MiB storage limit is applied.
  static Uint8List sanitize(Uint8List bytes) => _sanitize(bytes).bytes;

  /// Accepts only a previously sanitised still image in a version-2 backup.
  /// The caller keeps the exact bytes, so repeated export/import cannot
  /// recompress a JPEG or silently add back image metadata.
  static void validateStoredPhoto(String mimeType, Uint8List bytes) {
    final decoded = _decode(bytes);
    if (mimeType != (decoded.$2 ? 'image/png' : 'image/jpeg') ||
        _hasPrivateMetadata(bytes, decoded.$2) ||
        !decoded.$1.exif.isEmpty ||
        (decoded.$1.textData?.isNotEmpty ?? false) ||
        decoded.$1.iccProfile != null) {
      throw const PhotoStoreException('A saved photo is not valid.');
    }
  }

  /// Adds or atomically replaces the one image of [kind] for [entryId].
  /// An invalid, oversized, or undecodable image leaves the old one intact.
  Future<JournalPhoto> put({
    required String entryId,
    required PhotoKind kind,
    required Uint8List bytes,
  }) async => (await putBatch(entryId: entryId, photos: {kind: bytes}))[kind]!;

  /// Saves both kinds in one database transaction. If [alreadySanitized] is
  /// true, each image is still decoded and checked for metadata before any
  /// existing photo is changed; exact bytes are kept without recompression.
  Future<Map<PhotoKind, JournalPhoto>> putBatch({
    required String entryId,
    required Map<PhotoKind, Uint8List> photos,
    bool alreadySanitized = false,
  }) async {
    if (photos.isEmpty) {
      return const {};
    }
    final prepared = _prepare(photos, alreadySanitized);
    final saved = await db.transaction(
      () => _writeBatchInTransaction(entryId, prepared),
    );
    db.notifyUpdates({TableUpdate('wine_journal_photos')});
    return saved;
  }

  /// Writes under a caller-owned transaction, for a journal and two-photo
  /// save that commits or rolls back as one operation. Do not call [putBatch]
  /// inside that transaction: a nested transaction can stall the web engine.
  Future<Map<PhotoKind, JournalPhoto>> putBatchInTransaction({
    required String entryId,
    required Map<PhotoKind, Uint8List> photos,
    bool alreadySanitized = false,
  }) async {
    if (photos.isEmpty) {
      return const {};
    }
    final prepared = _prepare(photos, alreadySanitized);
    final saved = await _writeBatchInTransaction(entryId, prepared);
    db.notifyUpdates({TableUpdate('wine_journal_photos')});
    return saved;
  }

  static Map<PhotoKind, _PreparedPhoto> _prepare(
    Map<PhotoKind, Uint8List> photos,
    bool alreadySanitized,
  ) => {
    for (final entry in photos.entries)
      entry.key: alreadySanitized
          ? _validatePrepared(entry.value)
          : _sanitize(entry.value),
  };

  Future<Map<PhotoKind, JournalPhoto>> _writeBatchInTransaction(
    String entryId,
    Map<PhotoKind, _PreparedPhoto> prepared,
  ) async {
    final now = utcNow(_clock);
    final entry = await (db.select(
      db.wineJournalEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (entry == null) {
      throw const PhotoStoreException('This wine is no longer in the cellar.');
    }
    final result = <PhotoKind, JournalPhoto>{};
    for (final entry in prepared.entries) {
      final kind = entry.key;
      final photo = entry.value;
      final existing = await _forKind(entryId, kind);
      final key = existing?.key ?? newUuid(random);
      if (existing == null) {
        await db.customStatement(
          'INSERT INTO wine_journal_photos '
          '(id, wine_journal_entry_id, kind, mime_type, photo_bytes, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            key,
            entryId,
            kind.name,
            photo.mimeType,
            photo.bytes,
            now.toIso8601String(),
          ],
        );
      } else {
        await db.customStatement(
          'UPDATE wine_journal_photos SET mime_type = ?, photo_bytes = ?, '
          'created_at = ? WHERE id = ?',
          [photo.mimeType, photo.bytes, now.toIso8601String(), key],
        );
      }
      result[kind] = JournalPhoto(
        key: key,
        entryId: entryId,
        kind: kind,
        mimeType: photo.mimeType,
        createdAt: now,
      );
    }
    return result;
  }

  /// Returns null when a photo was deleted or its journal entry is gone.
  Future<Uint8List?> read(String key) async {
    final row = await db
        .customSelect(
          'SELECT photo_bytes FROM wine_journal_photos WHERE id = ?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    return row?.read<Uint8List>('photo_bytes');
  }

  Future<void> delete(String key) async {
    await db.customStatement('DELETE FROM wine_journal_photos WHERE id = ?', [
      key,
    ]);
    db.notifyUpdates({TableUpdate('wine_journal_photos')});
  }

  /// Watches metadata only; it never selects the potentially large BLOB.
  Stream<List<JournalPhoto>> watchForEntry(String entryId) => db
      .customSelect(
        'SELECT id, wine_journal_entry_id, kind, mime_type, created_at '
        'FROM wine_journal_photos WHERE wine_journal_entry_id = ? '
        'ORDER BY kind',
        variables: [Variable.withString(entryId)],
        readsFrom: {db.wineJournalPhotos, db.wineJournalEntries},
      )
      .watch()
      .map((rows) => rows.map(_photo).toList(growable: false));

  Future<JournalPhoto?> _forKind(String entryId, PhotoKind kind) async {
    final row = await db
        .customSelect(
          'SELECT id, wine_journal_entry_id, kind, mime_type, created_at '
          'FROM wine_journal_photos WHERE wine_journal_entry_id = ? AND kind = ?',
          variables: [
            Variable.withString(entryId),
            Variable.withString(kind.name),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _photo(row);
  }

  JournalPhoto _photo(QueryRow row) {
    final timestamp = row.data['created_at'];
    return JournalPhoto(
      key: row.read<String>('id'),
      entryId: row.read<String>('wine_journal_entry_id'),
      kind: PhotoKind.values.byName(row.read<String>('kind')),
      mimeType: row.read<String>('mime_type'),
      createdAt: timestamp is DateTime
          ? timestamp.toUtc()
          : DateTime.parse(timestamp! as String).toUtc(),
    );
  }

  static _PreparedPhoto _sanitize(Uint8List bytes) {
    final (decoded, isPng) = _decode(bytes, forImport: true);
    final orientation = decoded.exif.imageIfd.orientation;
    final upright = orientation == null || orientation == 1
        ? decoded
        : image.bakeOrientation(decoded);
    final longest = max(upright.width, upright.height);
    final scaled = longest > maxStoredDimension
        ? image.copyResize(
            upright,
            width: max(
              1,
              (upright.width * maxStoredDimension / longest).round(),
            ),
            height: max(
              1,
              (upright.height * maxStoredDimension / longest).round(),
            ),
            interpolation: image.Interpolation.linear,
          )
        : upright;
    scaled.exif = image.ExifData();
    scaled.textData = null;
    scaled.iccProfile = null;
    var storedAsPng = isPng;
    var clean = storedAsPng
        ? image.encodePng(scaled)
        : image.encodeJpg(scaled, quality: 85);
    // A full-resolution desktop PNG can be much larger than its JPEG photo.
    // Keep PNG when it fits, but still admit the photo when it does not.
    if (storedAsPng && clean.length > maxBytes) {
      clean = image.encodeJpg(scaled, quality: 85);
      storedAsPng = false;
    }
    if (clean.isEmpty || clean.length > maxBytes) {
      throw const PhotoStoreException('Choose a photo smaller than 8 MB.');
    }
    return _PreparedPhoto(storedAsPng ? 'image/png' : 'image/jpeg', clean);
  }

  static _PreparedPhoto _validatePrepared(Uint8List bytes) {
    final decoded = _decode(bytes);
    final mimeType = decoded.$2 ? 'image/png' : 'image/jpeg';
    if (_hasPrivateMetadata(bytes, decoded.$2) ||
        !decoded.$1.exif.isEmpty ||
        (decoded.$1.textData?.isNotEmpty ?? false) ||
        decoded.$1.iccProfile != null) {
      throw const PhotoStoreException('A saved photo is not valid.');
    }
    return _PreparedPhoto(mimeType, bytes);
  }

  static bool _hasPrivateMetadata(Uint8List bytes, bool isPng) {
    if (isPng) {
      var p = 8;
      while (p + 12 <= bytes.length) {
        final size =
            (bytes[p] << 24) |
            (bytes[p + 1] << 16) |
            (bytes[p + 2] << 8) |
            bytes[p + 3];
        if (size < 0 || p + 12 + size > bytes.length) {
          return true;
        }
        final type = String.fromCharCodes(bytes.sublist(p + 4, p + 8));
        if (const {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'iCCP'}.contains(type)) {
          return true;
        }
        p += 12 + size;
        if (type == 'IEND') {
          return p != bytes.length;
        }
      }
      return true;
    }
    if (bytes.length < 4 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes[bytes.length - 1] != 0xd9) {
      return true;
    }
    var p = 2;
    while (p + 3 < bytes.length) {
      if (bytes[p++] != 0xff) {
        return true;
      }
      while (p < bytes.length && bytes[p] == 0xff) {
        p++;
      }
      if (p >= bytes.length) {
        return true;
      }
      final marker = bytes[p++];
      if (marker == 0xda) {
        return false;
      }
      if (marker == 0xfe || (marker >= 0xe1 && marker <= 0xef)) {
        return true;
      }
      if (p + 1 >= bytes.length) {
        return true;
      }
      final length = (bytes[p] << 8) | bytes[p + 1];
      if (length < 2 || p + length > bytes.length) {
        return true;
      }
      p += length;
    }
    return true;
  }

  static (image.Image, bool) _decode(
    Uint8List bytes, {
    bool forImport = false,
  }) {
    if (bytes.isEmpty ||
        bytes.length > (forImport ? maxImportBytes : maxBytes)) {
      throw PhotoStoreException(
        forImport
            ? 'Choose a photo smaller than 24 MB.'
            : 'Choose a photo smaller than 8 MB.',
      );
    }
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final isPng =
        bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    if (!isJpeg && !isPng) {
      throw const PhotoStoreException('Choose a JPEG or PNG photo.');
    }
    // Preflight dimensions before a decoder allocates the pixel buffer.
    final dimensions = isPng ? _pngDimensions(bytes) : _jpegDimensions(bytes);
    if (dimensions == null ||
        dimensions.$1 <= 0 ||
        dimensions.$2 <= 0 ||
        dimensions.$1 > maxDimension ||
        dimensions.$2 > maxDimension ||
        dimensions.$1 * dimensions.$2 >
            (forImport ? maxImportPixels : maxPixels)) {
      throw PhotoStoreException(
        forImport
            ? 'Choose a photo up to 24 megapixels and 6000 pixels per side.'
            : 'This photo is too large to store.',
      );
    }
    image.Image? decoded;
    try {
      decoded = isPng ? image.decodePng(bytes) : image.decodeJpg(bytes);
    } catch (_) {
      throw const PhotoStoreException('The photo could not be read.');
    }
    if (decoded == null || decoded.hasAnimation) {
      throw const PhotoStoreException('The photo could not be read.');
    }
    return (decoded, isPng);
  }

  static (int, int)? _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24 ||
        bytes[12] != 0x49 ||
        bytes[13] != 0x48 ||
        bytes[14] != 0x44 ||
        bytes[15] != 0x52) {
      return null;
    }
    int word(int start) =>
        (bytes[start] << 24) |
        (bytes[start + 1] << 16) |
        (bytes[start + 2] << 8) |
        bytes[start + 3];
    return (word(16), word(20));
  }

  static (int, int)? _jpegDimensions(Uint8List bytes) {
    var p = 2;
    while (p + 3 < bytes.length) {
      if (bytes[p++] != 0xff) {
        return null;
      }
      while (p < bytes.length && bytes[p] == 0xff) {
        p++;
      }
      if (p >= bytes.length) {
        return null;
      }
      final marker = bytes[p++];
      if (marker == 0xd9 || marker == 0xda) {
        return null;
      }
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        continue;
      }
      if (p + 1 >= bytes.length) {
        return null;
      }
      final length = (bytes[p] << 8) | bytes[p + 1];
      if (length < 2 || p + length > bytes.length) {
        return null;
      }
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        if (length < 7) {
          return null;
        }
        final height = (bytes[p + 3] << 8) | bytes[p + 4];
        final width = (bytes[p + 5] << 8) | bytes[p + 6];
        return (width, height);
      }
      p += length;
    }
    return null;
  }
}

class _PreparedPhoto {
  const _PreparedPhoto(this.mimeType, this.bytes);

  final String mimeType;
  final Uint8List bytes;
}

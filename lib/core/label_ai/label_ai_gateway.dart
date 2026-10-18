import 'dart:typed_data';

import 'label_ai_client.dart';
import 'label_ai_result.dart';
import 'secret_store.dart';

/// What the learner has set up for the online label reader.
class LabelAiSettings {
  const LabelAiSettings({
    required this.hasKey,
    required this.enabled,
    required this.consented,
  });

  const LabelAiSettings.off()
    : hasKey = false,
      enabled = false,
      consented = false;

  final bool hasKey;

  /// The learner has switched the reader on and a key is saved.
  final bool enabled;

  /// The learner has read, once, that photos leave the phone for this.
  final bool consented;
}

/// The learner's key and choices, and the one place a reading starts. The key
/// lives in a [SecretStore], never in the database.
class LabelAiGateway {
  LabelAiGateway(
    this._store, {
    LabelAiClient Function(String key)? clientFor,
    Future<Uint8List?> Function(Uint8List photo)? prepare,
  }) : _clientFor = clientFor ?? ((key) => LabelAiClient(apiKey: key)),
       _prepare = prepare ?? ((photo) async => photo);

  static const keyName = 'label_ai_key';
  static const enabledName = 'label_ai_enabled';
  static const consentName = 'label_ai_consent';

  final SecretStore _store;
  final LabelAiClient Function(String key) _clientFor;
  final Future<Uint8List?> Function(Uint8List photo) _prepare;

  /// False where the platform has no safe place for a key.
  bool get isAvailable => _store.isAvailable;

  Future<LabelAiSettings> status() async {
    if (!_store.isAvailable) return const LabelAiSettings.off();
    final key = await _store.read(keyName);
    final hasKey = key != null && key.isNotEmpty;
    return LabelAiSettings(
      hasKey: hasKey,
      enabled: hasKey && await _store.read(enabledName) == '1',
      consented: await _store.read(consentName) == '1',
    );
  }

  /// Why [key] cannot be a key, or null when it looks like one. The service
  /// has the final say; this only catches a paste that went wrong.
  static String? keyProblem(String key) {
    final trimmed = key.trim();
    if (trimmed.length < 20) return 'That is too short to be an API key.';
    if (RegExp(r'[^\x21-\x7E]').hasMatch(trimmed)) {
      return 'An API key has no spaces or special characters. Paste it again.';
    }
    return null;
  }

  /// Saves [key] and switches the reader on.
  Future<void> saveKey(String key) async {
    final problem = keyProblem(key);
    if (problem != null) throw ArgumentError(problem);
    await _store.write(keyName, key.trim());
    await _store.write(enabledName, '1');
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      final key = await _store.read(keyName);
      if (key == null || key.isEmpty) return;
    }
    await _store.write(enabledName, enabled ? '1' : '0');
  }

  Future<void> removeKey() async {
    await _store.delete(keyName);
    await _store.delete(enabledName);
  }

  Future<void> giveConsent() => _store.write(consentName, '1');

  /// Sends [photos] (one to four, any image format) and returns what the
  /// reader found. Throws [LabelAiException] for every foreseeable failure.
  Future<LabelAiResult> read(List<Uint8List> photos) async {
    final key = await _store.read(keyName);
    if (key == null || key.isEmpty || await _store.read(enabledName) != '1') {
      throw const LabelAiException(
        LabelAiFailure.noKey,
        'Switch on the online reader and add your API key in Settings.',
      );
    }
    final prepared = <Uint8List>[];
    for (final photo in photos.take(LabelAiClient.maxPhotos)) {
      final jpeg = await _prepare(photo);
      if (jpeg != null) prepared.add(jpeg);
    }
    final client = _clientFor(key);
    try {
      return await client.read(prepared);
    } finally {
      client.close();
    }
  }
}

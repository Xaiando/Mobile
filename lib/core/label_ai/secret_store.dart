/// Somewhere to keep the learner's API key that is not the study database, so
/// that no export, backup file or review ZIP can carry it.
abstract class SecretStore {
  /// False where the platform has no safe place for a secret; the online
  /// reader is then not offered.
  bool get isAvailable;

  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// Keeps secrets in memory: for tests, and never used by the app itself.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async => _values[name] = value;

  @override
  Future<void> delete(String name) async => _values.remove(name);
}

/// The store on platforms with no safe place for a secret.
class UnavailableSecretStore implements SecretStore {
  const UnavailableSecretStore();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> read(String name) async => null;

  @override
  Future<void> write(String name, String value) async =>
      throw UnsupportedError('This device has no safe place for a key.');

  @override
  Future<void> delete(String name) async {}
}

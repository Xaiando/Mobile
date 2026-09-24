/// How durable the on-device database is.
///
/// Native platforms always store a file. On the web, Drift picks the best
/// storage the browser allows, and some choices do not keep data safely.
enum StorageDurability {
  /// Data persists and stays consistent across tabs.
  persistent,

  /// Data persists, but several open tabs can corrupt it (IndexedDB without a
  /// shared worker).
  singleTabOnly,

  /// Nothing survives a reload.
  memoryOnly;

  /// Maps the name of Drift's chosen web storage implementation.
  ///
  /// Matching on the name keeps `package:drift/wasm.dart`, which only compiles
  /// for the web, out of code that is also built for native platforms.
  static StorageDurability fromWebImplementation(String name) => switch (name) {
    'inMemory' => memoryOnly,
    'unsafeIndexedDb' => singleTabOnly,
    _ => persistent,
  };
}

/// Receives the durability of the web database once it has been opened.
///
/// Stays [StorageDurability.persistent] on native platforms, where Drift never
/// reports a web storage choice.
class StorageReport {
  StorageDurability durability = StorageDurability.persistent;
}

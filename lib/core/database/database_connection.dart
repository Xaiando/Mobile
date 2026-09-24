import 'package:drift_flutter/drift_flutter.dart';

import 'app_database.dart';
import 'storage_durability.dart';

/// Opens the on-device database: a file on native platforms, and Drift's
/// WASM backend on the web.
///
/// [onWebStorage] reports how durable the web storage Drift chose is. It is
/// never called on native platforms.
///
/// This lives apart from [AppDatabase] because it needs Flutter; the
/// database class itself does not, so tools run it with `dart run`.
AppDatabase openAppDatabase({void Function(StorageDurability)? onWebStorage}) {
  return AppDatabase(
    driftDatabase(
      name: 'sommelier',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
        onResult: (result) => onWebStorage?.call(
          StorageDurability.fromWebImplementation(
            result.chosenImplementation.name,
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'storage_durability.dart';

/// The open database. main.dart overrides it with [AppDatabase.open]; tests
/// override it with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'Override appDatabaseProvider in the root ProviderScope.',
  ),
);

/// Where the web storage choice is recorded when the database opens.
final storageReportProvider = Provider<StorageReport>((ref) => StorageReport());

/// Opens the database (running migrations) and reports how durable it is.
///
/// Drift connects lazily, so this is also what triggers the web storage choice.
final appStartupProvider = FutureProvider<StorageDurability>((ref) async {
  final database = ref.watch(appDatabaseProvider);
  await database.customSelect('SELECT 1').get();
  return ref.watch(storageReportProvider).durability;
});

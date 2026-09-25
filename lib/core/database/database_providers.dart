import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'storage_durability.dart';

/// The open database. main.dart overrides it with `openAppDatabase`; tests
/// override it with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'Override appDatabaseProvider in the root ProviderScope.',
  ),
);

/// Where the web storage choice is recorded when the database opens.
final storageReportProvider = Provider<StorageReport>((ref) => StorageReport());

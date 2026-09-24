import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/database/database_providers.dart';
import 'core/database/storage_durability.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageReport();
  final database = AppDatabase.open(
    onWebStorage: (durability) => storage.durability = durability,
  );
  runApp(
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        storageReportProvider.overrideWithValue(storage),
      ],
      child: const SommelierApp(),
    ),
  );
}

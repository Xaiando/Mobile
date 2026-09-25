import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'user_data_backup.dart';

final userDataBackupProvider = Provider<UserDataBackup>(
  (ref) => UserDataBackup(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

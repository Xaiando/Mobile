import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'user_settings.dart';

final learnerSettingsProvider = Provider<LearnerSettings>(
  (ref) => LearnerSettings(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

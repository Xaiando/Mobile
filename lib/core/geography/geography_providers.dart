import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'geometry_repository.dart';

final geometryRepositoryProvider = Provider<GeometryRepository>(
  (ref) => GeometryRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

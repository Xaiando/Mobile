import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../tasting_guidance/guided_tasting_providers.dart';
import '../time/time_providers.dart';
import 'tasting_pair.dart';

final tastingPairRepositoryProvider = FutureProvider<TastingPairRepository>(
  (ref) async => TastingPairRepository(
    ref.watch(appDatabaseProvider),
    guidance: await ref.watch(guidedTastingRepositoryProvider.future),
    clock: ref.watch(clockProvider),
  ),
);

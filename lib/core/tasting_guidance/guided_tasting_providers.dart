import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'guided_tasting.dart';

final guidedTastingBankProvider = FutureProvider<GuidedTastingBank>(
  (ref) async => GuidedTastingBank.fromJson(
    await rootBundle.loadString('assets/study/guided_tasting.json'),
  ),
);
final guidedTastingRepositoryProvider = FutureProvider<GuidedTastingRepository>(
  (ref) async {
    await ref.watch(appStartupProvider.future);
    return GuidedTastingRepository(
      ref.watch(appDatabaseProvider),
      bank: await ref.watch(guidedTastingBankProvider.future),
      clock: ref.watch(clockProvider),
    );
  },
);

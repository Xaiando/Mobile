import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'rehearsal.dart';

final rehearsalBankProvider = FutureProvider<RehearsalBank>(
  (ref) async => RehearsalBank.fromJson(
    await rootBundle.loadString('assets/study/wset_rehearsal.json'),
  ),
);

final rehearsalRepositoryProvider = FutureProvider<RehearsalRepository>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return RehearsalRepository(
    ref.watch(appDatabaseProvider),
    bank: await ref.watch(rehearsalBankProvider.future),
    clock: ref.watch(clockProvider),
  );
});

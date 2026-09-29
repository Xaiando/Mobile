import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'diploma_tasting_flight.dart';

final diplomaTastingBankProvider = FutureProvider<DiplomaTastingBank>(
  (ref) async => DiplomaTastingBank.fromJson(
    await rootBundle.loadString('assets/study/diploma_tasting_flights.json'),
  ),
);

final diplomaTastingFlightRepositoryProvider =
    FutureProvider<DiplomaTastingFlightRepository>((ref) async {
      await ref.watch(appStartupProvider.future);
      return DiplomaTastingFlightRepository(
        ref.watch(appDatabaseProvider),
        bank: await ref.watch(diplomaTastingBankProvider.future),
        clock: ref.watch(clockProvider),
      );
    });

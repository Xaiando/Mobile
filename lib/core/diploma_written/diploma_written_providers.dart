import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'diploma_written.dart';

final diplomaWrittenBankProvider = FutureProvider<DiplomaWrittenBank>(
  (ref) async => DiplomaWrittenBank.fromJson(
    await rootBundle.loadString('assets/study/diploma_written_practice.json'),
  ),
);

final diplomaWrittenRepositoryProvider =
    FutureProvider<DiplomaWrittenRepository>((ref) async {
      await ref.watch(appStartupProvider.future);
      return DiplomaWrittenRepository(
        ref.watch(appDatabaseProvider),
        bank: await ref.watch(diplomaWrittenBankProvider.future),
        clock: ref.watch(clockProvider),
      );
    });

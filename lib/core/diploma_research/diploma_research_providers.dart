import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'diploma_research.dart';

final diplomaResearchRepositoryProvider =
    FutureProvider<DiplomaResearchRepository>((ref) async {
      await ref.watch(appStartupProvider.future);
      return DiplomaResearchRepository(
        ref.watch(appDatabaseProvider),
        clock: ref.watch(clockProvider),
      );
    });

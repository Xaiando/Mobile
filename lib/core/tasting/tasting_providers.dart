import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'tasting_practice.dart';

final tastingPracticeProvider = Provider<TastingPractice>(
  (ref) => TastingPractice(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Every tasting session, the most recent first.
final tastingSessionsProvider = StreamProvider<List<TastingSession>>(
  (ref) => ref.watch(tastingPracticeProvider).watchSessions(),
);

/// The sessions about one wine in the journal.
final wineTastingsProvider =
    StreamProvider.family<List<TastingSession>, String>(
      (ref, entryId) => ref
          .watch(tastingPracticeProvider)
          .watchSessions(journalEntryId: entryId),
    );

final tastingSessionProvider = StreamProvider.family<TastingSession?, String>(
  (ref, id) => ref.watch(tastingPracticeProvider).watchSession(id),
);

/// A session's answers, by attribute.
final tastingAnswersProvider =
    StreamProvider.family<Map<String, Set<String>>, String>(
      (ref, id) => ref.watch(tastingPracticeProvider).watchAnswers(id),
    );

/// A grid's layout, which never changes while the app runs.
final gridLayoutProvider = FutureProvider.family<GridLayout, String>(
  (ref, id) => ref.watch(tastingPracticeProvider).layout(id),
);

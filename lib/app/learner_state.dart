import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/database/database_providers.dart';
import '../core/study/study_planner.dart';
import '../core/study/study_providers.dart';
import 'startup.dart';

// The learner's state as the screens see it. Each provider waits for startup
// (the curriculum ingested, the scheduler configured), then follows the
// database through Drift streams.

/// The certification profile; null until the learner picks a track.
final learnerProfileProvider = StreamProvider<UserProfile?>((ref) async* {
  await ref.watch(appStartupProvider.future);
  yield* ref.watch(learnerProfilesProvider).watch();
});

/// The tracks on offer: WSET Level 3 and CMS Certified (spec §N).
final selectableTracksProvider = FutureProvider<List<Certification>>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(learnerProfilesProvider).selectableTracks();
});

/// The Home dashboard's summary; null until a track is picked.
final studyOverviewProvider = StreamProvider<StudyOverview?>((ref) async* {
  await ref.watch(appStartupProvider.future);
  final planner = ref.watch(studyPlannerProvider);
  yield* planner.watch(planner.overview);
});

/// Every item of the active track with its memory state; null until a track
/// is picked.
final trackCardsProvider = StreamProvider<List<StudyCard>?>((ref) async* {
  await ref.watch(appStartupProvider.future);
  final planner = ref.watch(studyPlannerProvider);
  final profiles = ref.watch(learnerProfilesProvider);
  yield* planner.watch(() async {
    final profile = await profiles.current();
    return profile == null
        ? null
        : planner.cards(profile.activeCertificationId);
  });
});

/// The curriculum domains, in display order.
final curriculumDomainsProvider = FutureProvider<List<CurriculumDomain>>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.curriculumDomains,
  )..orderBy([(d) => OrderingTerm(expression: d.position)])).get();
});

/// The sources that support an item, with the locator within each.
final itemCitationsProvider = FutureProvider.autoDispose
    .family<List<(SourceCitation, String?)>, String>((ref, itemId) async {
      final db = ref.watch(appDatabaseProvider);
      final rows = await db
          .customSelect(
            '''
      SELECT s.*, c.locator FROM knowledge_item_citations c
      JOIN source_citations s ON s.id = c.source_citation_id
      WHERE c.knowledge_item_id = ?1
      ORDER BY s.title''',
            variables: [Variable(itemId)],
            readsFrom: {db.knowledgeItemCitations, db.sourceCitations},
          )
          .get();
      return [
        for (final row in rows)
          (
            db.sourceCitations.map(row.data),
            row.readNullable<String>('locator'),
          ),
      ];
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/curriculum/curriculum_catalog.dart';
import '../core/curriculum/curriculum_providers.dart';
import '../core/database/app_database.dart';
import '../core/settings/settings_providers.dart';
import '../core/settings/user_settings.dart';
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

/// The learner's settings; loading until startup has finished.
final settingsProvider = StreamProvider<SettingsSnapshot>((ref) async* {
  await ref.watch(appStartupProvider.future);
  yield* ref.watch(learnerSettingsProvider).watch();
});

/// Every source of the curriculum, for the About screen.
final allSourcesProvider = FutureProvider<List<SourceCitation>>((ref) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(curriculumCatalogProvider).allSources();
});

/// The installed curriculum release.
final installedReleaseProvider = FutureProvider<CurriculumRelease?>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(curriculumCatalogProvider).installedRelease();
});

/// The curriculum domains, in display order.
final curriculumDomainsProvider = FutureProvider<List<CurriculumDomain>>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(curriculumCatalogProvider).domains();
});

/// The sources that support an item, with the locator within each.
final itemSourcesProvider = FutureProvider.autoDispose
    .family<List<ItemSource>, String>(
      (ref, itemId) => ref.watch(curriculumCatalogProvider).sourcesOf(itemId),
    );

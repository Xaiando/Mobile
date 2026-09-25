import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/learner_state.dart';
import '../../app/startup.dart';
import '../../core/database/app_database.dart';
import '../../core/journal/journal_providers.dart';
import '../../core/tasting/tasting_providers.dart';
import '../../core/time/utc_clock.dart';
import '../cellar/cellar_screen.dart';

/// The tasting grids, once the curriculum is installed.
final tastingGridsProvider = FutureProvider<List<TastingGrid>>((ref) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(tastingPracticeProvider).grids();
});

/// The grid of the learner's track; null until they pick a track.
final trackGridProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(learnerProfileProvider.future);
  if (profile == null) return null;
  return ref
      .watch(tastingPracticeProvider)
      .gridFor(profile.activeCertificationId);
});

/// Tasting (spec Phase 4, backlog T2): practice describing wines on the
/// app's own grids. Each tasting is saved as it goes and can be resumed.
class TastingScreen extends ConsumerWidget {
  const TastingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(tastingSessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasting')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/tasting/new'),
        icon: const Icon(Icons.add),
        label: const Text('New tasting'),
      ),
      body: switch (sessions) {
        AsyncData(value: final list) when list.isEmpty => const _Empty(),
        AsyncData(value: final list) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => TastingSessionTile(list[index]),
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The tastings could not be read: $error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wine_bar_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Practise tasting', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Describe a wine step by step on the grid of your track, in a '
              'fixed set of terms. Each answer is saved as you go.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// When a tasting was finished, or started if it is still open.
String tastingDate(TastingSession session) {
  final done = session.completedAt;
  return done == null
      ? 'Started ${isoDate(session.startedAt.toLocal())}'
      : 'Finished ${isoDate(done.toLocal())}';
}

/// Whether [session] may show its wine: a blind tasting keeps it hidden
/// until the learner has finished.
bool showsWine(TastingSession session) =>
    !session.isBlind || session.completedAt != null;

class TastingSessionTile extends ConsumerWidget {
  const TastingSessionTile(this.session, {super.key, this.showWine = true});

  final TastingSession session;

  /// False where the wine is already on show, as on its journal entry.
  final bool showWine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridName = [
      for (final grid
          in ref.watch(tastingGridsProvider).value ?? const <TastingGrid>[])
        if (grid.id == session.tastingGridId) grid.displayName,
    ].firstOrNull;
    final wineId = session.wineJournalEntryId;
    final wine = wineId == null || !showWine || !showsWine(session)
        ? null
        : ref.watch(journalEntryProvider(wineId)).value;
    final open = session.completedAt == null;
    return ListTile(
      leading: CircleAvatar(
        child: Icon(open ? Icons.edit_note : Icons.task_alt),
      ),
      title: Text(wine == null ? gridName ?? 'Tasting' : journalTitle(wine)),
      subtitle: Text(
        [
          if (wine != null) ?gridName,
          tastingDate(session),
          if (session.isBlind) 'Blind',
          if (open) 'In progress',
        ].join(' · '),
      ),
      onTap: () => context.go('/tasting/${session.id}'),
    );
  }
}

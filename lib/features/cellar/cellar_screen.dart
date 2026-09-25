import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/journal/journal_providers.dart';

/// Cellar: the wine journal (spec §J, backlog J1). Each wine logged here is
/// linked to what the learner studies, and lifts those items in the queue.
class CellarScreen extends ConsumerWidget {
  const CellarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(journalEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cellar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/cellar/new'),
        icon: const Icon(Icons.add),
        label: const Text('Log a wine'),
      ),
      body: switch (entries) {
        AsyncData(value: final list) when list.isEmpty => const _Empty(),
        AsyncData(value: final list) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => JournalEntryTile(list[index]),
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The journal could not be read: $error'),
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
            Text('Your wine journal', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Log the wines you taste. Each one is linked to its region and '
              'grapes, and what you study about them comes up sooner.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The name a learner would call [entry] by: producer and cuvée, or else
/// the appellation or grapes they wrote.
String journalTitle(WineJournalEntry entry) {
  final parts = [?entry.producerName, ?entry.cuveeName];
  if (parts.isNotEmpty) return parts.join(' · ');
  return entry.appellationText ?? entry.grapesText ?? 'A wine';
}

/// What else identifies [entry]: appellation, vintage and grapes.
String journalSubtitle(WineJournalEntry entry) => [
  if (entry.producerName != null || entry.cuveeName != null)
    ?entry.appellationText,
  if (entry.isNonVintage) 'NV' else ?entry.vintage?.toString(),
  if (entry.producerName != null ||
      entry.cuveeName != null ||
      entry.appellationText != null)
    ?entry.grapesText,
].join(' · ');

class JournalEntryTile extends StatelessWidget {
  const JournalEntryTile(this.entry, {super.key});

  final WineJournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final subtitle = journalSubtitle(entry);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.wine_bar)),
      title: Text(journalTitle(entry)),
      subtitle: Text(
        [
          if (subtitle.isNotEmpty) subtitle,
          if (entry.tastedOn != null) 'Tasted ${entry.tastedOn}',
        ].join('\n'),
      ),
      isThreeLine: subtitle.isNotEmpty && entry.tastedOn != null,
      trailing: entry.rating == null ? null : RatingStars(entry.rating!),
      onTap: () => context.go('/cellar/${entry.id}'),
    );
  }
}

/// A 1–5 rating as stars (P-3).
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 18});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Rated $rating of 5',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= rating ? Icons.star : Icons.star_border,
                size: size,
                color: colour,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/journal/journal_providers.dart';
import '../../core/tasting/tasting_providers.dart';
import '../tasting/tasting_screen.dart';
import 'cellar_screen.dart';

/// One journal entry: what was written, and the knowledge it is linked to.
class JournalEntryScreen extends ConsumerWidget {
  const JournalEntryScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(journalEntryProvider(id));
    return switch (entry) {
      AsyncData(value: final entry?) => _EntryView(entry),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This entry no longer exists.')),
      ),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('The entry could not be read: $error')),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _EntryView extends ConsumerWidget {
  const _EntryView(this.entry);

  final WineJournalEntry entry;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'The wine leaves your journal and stops lifting the items it is '
          'linked to. Your study progress is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(wineJournalProvider).delete(entry.id);
    if (context.mounted) context.go('/cellar');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final links = ref.watch(journalLinksProvider(entry.id)).value ?? const [];
    final tastings =
        ref.watch(wineTastingsProvider(entry.id)).value ?? const [];
    final subtitle = journalSubtitle(entry);
    Widget fact(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(journalTitle(entry)),
        actions: [
          IconButton(
            tooltip: 'Taste this wine',
            icon: const Icon(Icons.wine_bar_outlined),
            onPressed: () => context.go('/tasting/new?wine=${entry.id}'),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.go('/cellar/${entry.id}/edit'),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(subtitle, style: theme.textTheme.titleMedium),
            ),
          if (entry.rating != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RatingStars(entry.rating!, size: 28),
            ),
          fact('Tasted', entry.tastedOn),
          fact('Producer', entry.producerName),
          fact('Cuvée', entry.cuveeName),
          fact('Appellation', entry.appellationText),
          fact('Grapes', entry.grapesText),
          fact(
            'Vintage',
            entry.isNonVintage ? 'Non-vintage' : entry.vintage?.toString(),
          ),
          fact(
            'Alcohol',
            entry.abvPercent == null ? null : '${entry.abvPercent} %',
          ),
          fact('Notes', entry.tastingNotes),
          const Divider(height: 32),
          Text('Linked to your studies', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (links.isEmpty)
            const Text(
              'Nothing yet. Edit the entry to link its region and grapes.',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final node in links)
                  Chip(
                    avatar: const Icon(Icons.link, size: 18),
                    label: Text(node.name),
                  ),
              ],
            ),
          if (tastings.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Tastings', style: theme.textTheme.titleSmall),
            for (final session in tastings)
              TastingSessionTile(session, showWine: false),
          ],
        ],
      ),
    );
  }
}

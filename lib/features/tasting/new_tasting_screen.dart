import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/journal/journal_providers.dart';
import '../../core/tasting/tasting_providers.dart';
import '../cellar/cellar_screen.dart';
import 'tasting_screen.dart';

/// Starts a tasting (backlog T2): on the grid of the learner's track unless
/// they pick the other one, blind or not, and optionally about a wine from
/// the journal, such as [wineId].
class NewTastingScreen extends ConsumerStatefulWidget {
  const NewTastingScreen({super.key, this.wineId});

  final String? wineId;

  @override
  ConsumerState<NewTastingScreen> createState() => _NewTastingScreenState();
}

class _NewTastingScreenState extends ConsumerState<NewTastingScreen> {
  /// The grid picked here; null for the track's grid.
  String? _gridId;

  /// A tasting of a known wine starts sighted; otherwise it starts blind.
  late bool _blind = widget.wineId == null;
  late String? _wineId = widget.wineId;
  bool _starting = false;

  Future<void> _start(String gridId) async {
    setState(() => _starting = true);
    try {
      final session = await ref
          .read(tastingPracticeProvider)
          .start(gridId, isBlind: _blind, journalEntryId: _wineId);
      if (mounted) context.go('/tasting/${session.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The tasting could not be started: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New tasting')),
      body: switch (ref.watch(tastingGridsProvider)) {
        AsyncData(value: final grids) when grids.isNotEmpty => _form(grids),
        AsyncData() => const Center(child: Text('No tasting grid installed.')),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The grids could not be read: $error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _form(List<TastingGrid> grids) {
    final theme = Theme.of(context);
    final trackGrid = ref.watch(trackGridProvider).value;
    final gridId =
        _gridId ??
        grids.map((g) => g.id).where((id) => id == trackGrid).firstOrNull ??
        grids.first.id;
    final wines = ref.watch(journalEntriesProvider).value ?? const [];
    final wineId = wines.any((w) => w.id == _wineId) ? _wineId : null;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        heading('Grid'),
        RadioGroup<String>(
          groupValue: gridId,
          onChanged: (id) => setState(() => _gridId = id),
          child: Column(
            children: [
              for (final grid in grids)
                RadioListTile<String>(
                  value: grid.id,
                  title: Text(grid.displayName),
                  subtitle: _GridSummary(grid, isTrack: grid.id == trackGrid),
                ),
            ],
          ),
        ),
        heading('The wine'),
        SwitchListTile(
          value: _blind,
          onChanged: (value) => setState(() => _blind = value),
          title: const Text('Blind tasting'),
          subtitle: Text(
            _blind
                ? 'The wine stays hidden until you finish.'
                : 'You know the wine as you taste.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: WinePicker(
            wines: wines,
            wineId: wineId,
            label: _blind
                ? 'Wine from your journal, revealed at the end'
                : 'Wine from your journal',
            onChanged: (id) => setState(() => _wineId = id),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: FilledButton.icon(
            onPressed: _starting ? null : () => _start(gridId),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start tasting'),
          ),
        ),
      ],
    );
  }
}

/// A grid's sections, and whether it is the grid of the learner's track.
class _GridSummary extends ConsumerWidget {
  const _GridSummary(this.grid, {required this.isTrack});

  final TastingGrid grid;
  final bool isTrack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(gridLayoutProvider(grid.id)).value?.sections;
    return Text(
      [
        if (sections != null) sections.join(', '),
        if (isTrack) 'The grid of your track',
      ].join('\n'),
    );
  }
}

/// Picks a wine from the journal, or none.
class WinePicker extends StatelessWidget {
  const WinePicker({
    super.key,
    required this.wines,
    required this.wineId,
    required this.label,
    required this.onChanged,
  });

  final List<WineJournalEntry> wines;
  final String? wineId;
  final String label;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (wines.isEmpty) {
      return Text(
        'Log a wine in the Cellar to link your tastings to it.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: wineId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('No wine')),
        for (final wine in wines)
          DropdownMenuItem(
            value: wine.id,
            child: Text(
              [
                journalTitle(wine),
                if (journalSubtitle(wine) case final s when s.isNotEmpty) s,
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/journal/journal_providers.dart';
import '../../core/tasting/tasting_practice.dart';
import '../../core/tasting/tasting_providers.dart';
import '../cellar/cellar_screen.dart';
import 'new_tasting_screen.dart';
import 'tasting_screen.dart';

/// One tasting (backlog T2): a step for each section of its grid, then the
/// notes and the wine. Each answer is saved as it is chosen, so the learner
/// can leave and come back. A finished tasting shows what was found.
class TastingSessionScreen extends ConsumerWidget {
  const TastingSessionScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget message(String text) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
      ),
    );
    const loading = Scaffold(body: Center(child: CircularProgressIndicator()));
    return switch (ref.watch(tastingSessionProvider(id))) {
      AsyncData(value: final session?) => switch (ref.watch(
        gridLayoutProvider(session.tastingGridId),
      )) {
        AsyncData(value: final grid) => _SessionView(session, grid),
        AsyncError(:final error) => message(
          'The grid could not be read: $error',
        ),
        _ => loading,
      },
      AsyncData() => message('This tasting no longer exists.'),
      AsyncError(:final error) => message(
        'The tasting could not be read: $error',
      ),
      _ => loading,
    };
  }
}

class _SessionView extends ConsumerStatefulWidget {
  const _SessionView(this.session, this.grid);

  final TastingSession session;
  final GridLayout grid;

  @override
  ConsumerState<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends ConsumerState<_SessionView> {
  final _scroll = ScrollController();
  late final _notes = TextEditingController(text: widget.session.notes);
  late final TastingPractice _practice = ref.read(tastingPracticeProvider);
  late final _titleKeys = [
    for (var i = 0; i <= widget.grid.sections.length; i++) GlobalKey(),
  ];

  /// The open step; until the answers load, none. A resumed tasting opens
  /// at its first unfinished section.
  int? _step;

  /// Whether a finished tasting is shown as its grid again, to change it.
  bool _editing = false;

  /// Whether to mark what is missing: set when finishing fails.
  bool _showMissing = false;

  bool _finishing = false;
  bool _savingNotes = false;
  bool _notesChanged = false;

  TastingSession get session => widget.session;
  GridLayout get grid => widget.grid;

  @override
  void dispose() {
    _scroll.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Saves the notes as they are typed, one write at a time.
  Future<void> _saveNotes() async {
    if (_savingNotes) {
      _notesChanged = true;
      return;
    }
    _savingNotes = true;
    try {
      do {
        _notesChanged = false;
        await _practice.setNotes(session.id, _notes.text);
      } while (_notesChanged);
    } finally {
      _savingNotes = false;
    }
  }

  Future<void> _select(
    GridAttribute attribute,
    String valueKey,
    bool selected,
  ) async {
    try {
      await _practice.select(
        session.id,
        attribute.key,
        valueKey,
        selected: selected,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The answer could not be saved: $error')),
      );
    }
  }

  /// Opens step [to]. The steps above the lower of the two stay still while
  /// one closes and the other opens, so the view settles on that one.
  void _go(int to) {
    final from = _step ?? 0;
    setState(() => _step = to);
    final anchor = _titleKeys[min(from, to)].currentContext;
    if (anchor != null) {
      Scrollable.ensureVisible(
        anchor,
        duration: kThemeAnimationDuration,
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  List<GridAttribute> _missingIn(
    String section,
    Map<String, Set<String>> answers,
  ) => [
    for (final attribute in grid.missing(answers))
      if (attribute.attribute.section == section) attribute,
  ];

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await _saveNotes();
    final missing = await _practice.complete(session.id);
    if (!mounted) return;
    setState(() {
      _finishing = false;
      _showMissing = missing.isNotEmpty;
      if (missing.isEmpty) _editing = false;
    });
    if (missing.isEmpty) return;
    _go(grid.sections.indexOf(missing.first.attribute.section));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Answer the rest of the grid first: '
          '${missing.map((a) => a.attribute.label).join(', ')}.',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this tasting?'),
        content: const Text('Its answers and notes are deleted too.'),
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
    if (confirmed != true || !mounted) return;
    await _practice.delete(session.id);
    if (mounted) context.go('/tasting');
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(tastingAnswersProvider(session.id));
    final finished = session.completedAt != null && !_editing;
    return Scaffold(
      appBar: AppBar(
        title: Text(grid.grid.displayName),
        actions: [
          if (finished)
            IconButton(
              tooltip: 'Change answers',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: switch (answers) {
        AsyncData(value: final answers) when finished => _Summary(
          session: session,
          grid: grid,
          answers: answers,
        ),
        AsyncData(value: final answers) => _stepper(answers),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The answers could not be read: $error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _stepper(Map<String, Set<String>> answers) {
    final sections = grid.sections;
    final last = sections.length;
    final step = _step ??= [
      for (final (i, section) in sections.indexed)
        if (_missingIn(section, answers).isNotEmpty) i,
      last,
    ].first;
    final wines = ref.watch(journalEntriesProvider).value ?? const [];
    final wineId = wines.any((w) => w.id == session.wineJournalEntryId)
        ? session.wineJournalEntryId
        : null;

    return Stepper(
      controller: _scroll,
      currentStep: step,
      onStepTapped: (index) => setState(() => _step = index),
      onStepContinue: () => _go(step + 1),
      onStepCancel: () => _go(step - 1),
      controlsBuilder: (context, details) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (details.stepIndex == last)
              FilledButton(
                key: const ValueKey('tasting-step-finish'),
                onPressed: _finishing ? null : _finish,
                child: const Text('Finish tasting'),
              )
            else
              FilledButton.tonal(
                key: ValueKey('tasting-step-next-${details.stepIndex}'),
                onPressed: details.onStepContinue,
                child: const Text('Next'),
              ),
            if (details.stepIndex > 0)
              TextButton(
                onPressed: details.onStepCancel,
                child: const Text('Back'),
              ),
          ],
        ),
      ),
      steps: [
        for (final (i, section) in sections.indexed)
          _sectionStep(i, section, answers, isActive: i == step),
        Step(
          title: Text('Notes and wine', key: _titleKeys[last]),
          isActive: step == last,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  helperText: 'Anything else you noticed. Saved as you type.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _saveNotes(),
              ),
              const SizedBox(height: 16),
              // A blind tasting of a wine chosen beforehand keeps its secret.
              if (session.isBlind && wineId != null)
                const Text('The wine is revealed when you finish.')
              else
                WinePicker(
                  wines: wines,
                  wineId: wineId,
                  label: session.isBlind
                      ? 'Which wine was it?'
                      : 'Wine from your journal',
                  onChanged: (id) => _practice.linkWine(session.id, id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Step _sectionStep(
    int index,
    String section,
    Map<String, Set<String>> answers, {
    required bool isActive,
  }) {
    final missing = _missingIn(section, answers);
    return Step(
      title: Text(section, key: _titleKeys[index]),
      subtitle: _showMissing && missing.isNotEmpty
          ? Text(
              'To answer: ${missing.map((a) => a.attribute.label).join(', ')}',
            )
          : null,
      isActive: isActive,
      state: missing.isEmpty
          ? StepState.complete
          : _showMissing
          ? StepState.error
          : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final attribute in grid.inSection(section))
            _AttributeField(
              attribute,
              chosen: answers[attribute.key] ?? const {},
              isMissing: _showMissing && missing.contains(attribute),
              onSelected: (value, selected) =>
                  _select(attribute, value, selected),
            ),
        ],
      ),
    );
  }
}

/// One attribute's choices: one value, or any that apply.
class _AttributeField extends StatelessWidget {
  const _AttributeField(
    this.attribute, {
    required this.chosen,
    required this.isMissing,
    required this.onSelected,
  });

  final GridAttribute attribute;
  final Set<String> chosen;
  final bool isMissing;

  /// Called with a value and whether it is now chosen.
  final void Function(String valueKey, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('tasting-attribute-${attribute.key}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            attribute.isSingle
                ? attribute.attribute.label
                : '${attribute.attribute.label} (any that apply)',
            style: theme.textTheme.titleSmall,
          ),
          if (isMissing)
            Text(
              'Choose one',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in attribute.values)
                if (attribute.isSingle)
                  ChoiceChip(
                    label: Text(value.label),
                    selected: chosen.contains(value.valueKey),
                    onSelected: (selected) =>
                        onSelected(value.valueKey, selected),
                  )
                else
                  FilterChip(
                    label: Text(value.label),
                    selected: chosen.contains(value.valueKey),
                    onSelected: (selected) =>
                        onSelected(value.valueKey, selected),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A finished tasting: the wine, if revealed, and every answer by section.
class _Summary extends ConsumerWidget {
  const _Summary({
    required this.session,
    required this.grid,
    required this.answers,
  });

  final TastingSession session;
  final GridLayout grid;
  final Map<String, Set<String>> answers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wineId = session.wineJournalEntryId;
    final wine = wineId == null
        ? null
        : ref.watch(journalEntryProvider(wineId)).value;
    String labels(GridAttribute attribute) => [
      for (final value in attribute.values)
        if (answers[attribute.key]?.contains(value.valueKey) ?? false)
          value.label,
    ].join(', ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          [tastingDate(session), if (session.isBlind) 'Blind'].join(' · '),
          style: theme.textTheme.titleMedium,
        ),
        if (wine != null)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              leading: const Icon(Icons.wine_bar),
              title: Text(
                session.isBlind
                    ? 'The wine was ${journalTitle(wine)}'
                    : journalTitle(wine),
              ),
              subtitle: journalSubtitle(wine).isEmpty
                  ? null
                  : Text(journalSubtitle(wine)),
              onTap: () => context.go('/cellar/${wine.id}'),
            ),
          ),
        for (final section in grid.sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              section,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final attribute in grid.inSection(section))
            if (labels(attribute) case final text when text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attribute.attribute.label,
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(text, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
        ],
        if (session.notes case final notes?) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              'Notes',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Text(notes, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/startup.dart';
import '../../core/database/app_database.dart';
import '../../core/journal/journal_matcher.dart';
import '../../core/journal/journal_providers.dart';
import '../../core/journal/wine_journal.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';

/// The names the journal can link to, once the curriculum is installed.
final _matcherProvider = FutureProvider<JournalMatcher>((ref) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(journalMatcherProvider.future);
});

/// Creates an entry, or edits entry [id] (backlog J1). As the learner types,
/// it suggests the regions and grapes the text names; the learner confirms
/// which to link (J2).
class JournalEditor extends ConsumerStatefulWidget {
  const JournalEditor({super.key, this.id});

  final String? id;

  @override
  ConsumerState<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends ConsumerState<JournalEditor> {
  final _producer = TextEditingController();
  final _cuvee = TextEditingController();
  final _vintage = TextEditingController();
  final _appellation = TextEditingController();
  final _grapes = TextEditingController();
  final _abv = TextEditingController();
  final _notes = TextEditingController();
  String? _tastedOn;
  bool _isNonVintage = false;
  int? _rating;

  /// The nodes the learner has chosen to link.
  final _linked = <String>{};

  /// Nodes the learner has decided on, so a suggestion never re-selects
  /// something they turned off.
  final _decided = <String>{};

  /// Linked nodes that are no longer suggested by the text, kept on show.
  final _kept = <String, KnowledgeNode>{};

  /// Nodes selected only because the text named them exactly. If the text
  /// stops naming one, it is unselected again: a link the learner cannot
  /// see is never saved.
  final _auto = <String>{};

  bool _loaded = false;
  bool _saving = false;
  List<String> _problems = const [];

  bool get _isNew => widget.id == null;

  @override
  void initState() {
    super.initState();
    for (final controller in [_producer, _cuvee, _appellation, _grapes]) {
      controller.addListener(() => setState(() {}));
    }
    if (_isNew) {
      _tastedOn = localToday(ref.read(clockProvider));
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final journal = ref.read(wineJournalProvider);
    final entry = await journal.entry(widget.id!);
    final links = await journal.linkedNodes(widget.id!);
    if (!mounted) return;
    setState(() {
      if (entry != null) {
        _producer.text = entry.producerName ?? '';
        _cuvee.text = entry.cuveeName ?? '';
        _vintage.text = entry.vintage?.toString() ?? '';
        _appellation.text = entry.appellationText ?? '';
        _grapes.text = entry.grapesText ?? '';
        _abv.text = entry.abvPercent?.toString() ?? '';
        _notes.text = entry.tastingNotes ?? '';
        _tastedOn = entry.tastedOn;
        _isNonVintage = entry.isNonVintage;
        _rating = entry.rating;
      }
      for (final node in links) {
        _linked.add(node.id);
        _decided.add(node.id);
        _kept[node.id] = node;
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _producer,
      _cuvee,
      _vintage,
      _appellation,
      _grapes,
      _abv,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  JournalDraft _draft() => JournalDraft(
    tastedOn: _tastedOn,
    producerName: _producer.text,
    cuveeName: _cuvee.text,
    vintage: _isNonVintage ? null : int.tryParse(_vintage.text.trim()),
    isNonVintage: _isNonVintage,
    appellationText: _appellation.text,
    grapesText: _grapes.text,
    abvPercent: double.tryParse(_abv.text.trim().replaceAll(',', '.')),
    rating: _rating,
    tastingNotes: _notes.text,
  );

  /// Problems the draft cannot show: numbers the learner typed but that do
  /// not read as numbers.
  List<String> _typingProblems() => [
    if (!_isNonVintage &&
        _vintage.text.trim().isNotEmpty &&
        int.tryParse(_vintage.text.trim()) == null)
      'A vintage is a year, such as 2019.',
    if (_abv.text.trim().isNotEmpty &&
        double.tryParse(_abv.text.trim().replaceAll(',', '.')) == null)
      'Alcohol is a number, such as 13.5.',
  ];

  Future<void> _save() async {
    final draft = _draft();
    final problems = [..._typingProblems(), ...draft.problems];
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    setState(() => _saving = true);
    final journal = ref.read(wineJournalProvider);
    // Only the links on show: those the text suggests, and those kept.
    final shown = {
      ...?ref
          .read(_matcherProvider)
          .value
          ?.suggest(draft)
          .map((suggestion) => suggestion.node.id),
      ..._kept.keys,
    };
    final links = _linked.intersection(shown);
    try {
      final entry = _isNew
          ? await journal.create(draft, nodeIds: links)
          : await journal.update(widget.id!, draft, nodeIds: links);
      if (mounted) context.go('/cellar/${entry.id}');
    } on JournalDraftException catch (error) {
      setState(() {
        _problems = error.problems;
        _saving = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final initial = _tastedOn == null
        ? DateTime.now()
        : DateTime.parse(_tastedOn!);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _tastedOn = isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matcher = ref.watch(_matcherProvider).value;
    final suggestions = matcher?.suggest(_draft()) ?? const [];
    final suggested = {for (final s in suggestions) s.node.id};
    // An exact name the text no longer holds loses its automatic link.
    for (final id in _auto.difference(suggested).toList()) {
      _auto.remove(id);
      _decided.remove(id);
      _linked.remove(id);
    }
    for (final suggestion in suggestions) {
      if (suggestion.isLikely && _decided.add(suggestion.node.id)) {
        _linked.add(suggestion.node.id);
        _auto.add(suggestion.node.id);
      }
    }
    final kept = [
      for (final node in _kept.values)
        if (!suggested.contains(node.id)) node,
    ];

    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
      TextInputType? keyboard,
      int maxLines = 1,
      bool enabled = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Log a wine' : 'Edit entry'),
        actions: [
          TextButton(
            onPressed: _saving || !_loaded ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Above the form, so the learner sees why saving failed
                // wherever they have scrolled to.
                if (_problems.isNotEmpty)
                  Material(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      title: Text(
                        _problems.join('\n'),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                Expanded(child: _form(theme, suggestions, kept, field)),
              ],
            ),
    );
  }

  Widget _form(
    ThemeData theme,
    List<NodeSuggestion> suggestions,
    List<KnowledgeNode> kept,
    Widget Function(
      TextEditingController controller,
      String label, {
      String? hint,
      TextInputType? keyboard,
      int maxLines,
      bool enabled,
    })
    field,
  ) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      field(_producer, 'Producer'),
      field(_cuvee, 'Cuvée'),
      field(_appellation, 'Appellation or region', hint: 'e.g. Barolo'),
      field(_grapes, 'Grapes', hint: 'e.g. Nebbiolo'),
      Row(
        children: [
          Expanded(
            child: field(
              _vintage,
              'Vintage',
              keyboard: TextInputType.number,
              enabled: !_isNonVintage,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: field(
              _abv,
              'Alcohol %',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Non-vintage'),
        value: _isNonVintage,
        onChanged: (value) => setState(() => _isNonVintage = value),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: Text(
          _tastedOn == null ? 'No tasting date' : 'Tasted $_tastedOn',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tastedOn != null)
              TextButton(
                onPressed: () => setState(() => _tastedOn = null),
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: _pickDate,
              child: Text(_tastedOn == null ? 'Set' : 'Change'),
            ),
          ],
        ),
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Rating', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i of 5',
              icon: Icon(
                (_rating ?? 0) >= i ? Icons.star : Icons.star_border,
                color: theme.colorScheme.primary,
              ),
              onPressed: () =>
                  setState(() => _rating = _rating == i ? null : i),
            ),
        ],
      ),
      const SizedBox(height: 8),
      field(_notes, 'Tasting notes', maxLines: 4),
      const Divider(height: 24),
      Text('Link to your studies', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        'Items about linked places and grapes come up sooner in '
        'Practice.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      if (suggestions.isEmpty && kept.isEmpty)
        const Text('Type an appellation or grapes to see suggestions.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final suggestion in suggestions)
            FilterChip(
              label: Text(
                suggestion.isExact
                    ? '${suggestion.node.name} · '
                          '${suggestion.node.nodeType}'
                    : 'Did you mean ${suggestion.node.name}?',
              ),
              selected: _linked.contains(suggestion.node.id),
              onSelected: (on) => setState(() {
                _decided.add(suggestion.node.id);
                _auto.remove(suggestion.node.id);
                on
                    ? _linked.add(suggestion.node.id)
                    : _linked.remove(suggestion.node.id);
              }),
            ),
          for (final node in kept)
            FilterChip(
              label: Text('${node.name} · ${node.nodeType}'),
              selected: _linked.contains(node.id),
              onSelected: (on) => setState(
                () => on ? _linked.add(node.id) : _linked.remove(node.id),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_isNew ? 'Save to journal' : 'Save changes'),
      ),
    ],
  );
}

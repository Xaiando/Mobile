import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../app/startup.dart';
import '../../core/curriculum/name_normalizer.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_providers.dart';
import '../../core/study/study_planner.dart';
import '../../core/study/study_search.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';
import '../home/track_picker.dart';

/// Names supplement assertion text when searching the active track's cards.
/// Watching both authored tables keeps newly installed aliases searchable.
final _studyNodeNamesProvider = StreamProvider.autoDispose<Map<String, String>>(
  (ref) async* {
    await ref.watch(appStartupProvider.future);
    final db = ref.watch(appDatabaseProvider);
    yield* StudySearchIndex(db).watchNames();
  },
);

/// Study: the active track's curriculum by topic, with each item's memory
/// state, badges and sources (spec §M).
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(trackCardsProvider);
    final domains = ref.watch(curriculumDomainsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Study')),
      body: switch (cards) {
        AsyncData(value: null) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Choose the certification you are studying for to see '
                  'its curriculum.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                TrackPicker(),
              ],
            ),
          ),
        ),
        AsyncData(value: final cards?) => _Curriculum(
          key: ValueKey(
            ref.watch(learnerProfileProvider).value?.activeCertificationId,
          ),
          cards: cards,
          domains: domains,
        ),
        AsyncError(:final error) => Center(
          child: Text('The curriculum could not be read: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Curriculum extends ConsumerStatefulWidget {
  const _Curriculum({super.key, required this.cards, required this.domains});

  final List<StudyCard> cards;
  final List<CurriculumDomain> domains;

  @override
  ConsumerState<_Curriculum> createState() => _CurriculumState();
}

class _CurriculumState extends ConsumerState<_Curriculum> {
  final _search = TextEditingController();
  String? _domainId;
  List<StudyCard>? _indexedCards;
  List<CurriculumDomain>? _indexedDomains;
  Map<String, String>? _indexedNames;
  Map<String, String> _searchText = const {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() {
    _search.clear();
    setState(() => _domainId = null);
  }

  void _index(Map<String, String> nodeNames) {
    if (identical(_indexedCards, widget.cards) &&
        identical(_indexedDomains, widget.domains) &&
        identical(_indexedNames, nodeNames)) {
      return;
    }
    final domainNames = {
      for (final domain in widget.domains) domain.id: domain.displayName,
    };
    _searchText = {
      for (final card in widget.cards)
        card.itemId: normalizeName(
          [
            card.item.assertionText,
            domainNames[card.item.domainId] ?? card.item.domainId,
            nodeNames[card.item.subjectId] ?? '',
            nodeNames[card.item.objectId] ?? '',
          ].join(' '),
        ),
    };
    _indexedCards = widget.cards;
    _indexedDomains = widget.domains;
    _indexedNames = nodeNames;
  }

  @override
  Widget build(BuildContext context) {
    final now = utcNow(ref.watch(clockProvider));
    final theme = Theme.of(context);
    final nodeNames =
        ref.watch(_studyNodeNamesProvider).value ?? const <String, String>{};
    _index(nodeNames);
    final availableDomains = widget.cards
        .map((card) => card.item.domainId)
        .toSet();
    final selectedDomain = availableDomains.contains(_domainId)
        ? _domainId
        : null;
    final terms = normalizeName(_search.text)
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList();
    final matching = widget.cards.where((card) {
      if (selectedDomain != null && card.item.domainId != selectedDomain) {
        return false;
      }
      if (terms.isEmpty) return true;
      final text = _searchText[card.itemId]!;
      return terms.every(text.contains);
    }).toList();
    final byDomain = <String, List<StudyCard>>{};
    for (final card in matching) {
      byDomain.putIfAbsent(card.item.domainId, () => []).add(card);
    }
    final filtered = _search.text.isNotEmpty || selectedDomain != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('study-search'),
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search study',
              hintText: 'Wine, grape or topic',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            key: ValueKey('study-topic-${selectedDomain ?? 'all'}'),
            initialValue: selectedDomain ?? '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Focus on a topic',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('All topics', overflow: TextOverflow.ellipsis),
              ),
              for (final domain in widget.domains)
                if (availableDomains.contains(domain.id))
                  DropdownMenuItem(
                    value: domain.id,
                    child: Text(
                      domain.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onChanged: (value) => setState(() {
              _domainId = value == '' ? null : value;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${matching.length} of ${widget.cards.length} facts',
                key: const ValueKey('study-result-count'),
              ),
              if (filtered)
                TextButton(
                  onPressed: _reset,
                  child: const Text('Reset filters'),
                ),
            ],
          ),
        ),
        Expanded(
          child: matching.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.cards.isEmpty
                          ? 'No study material is available for this track yet.'
                          : 'No facts match these filters.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  key: const ValueKey('study-results'),
                  children: [
                    for (final domain in widget.domains)
                      if (byDomain[domain.id] case final domainCards?) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            '${domain.displayName} · ${domainCards.length}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        for (final card in domainCards)
                          ListTile(
                            title: Text(
                              card.item.assertionText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(memoryLabel(card, now)),
                            trailing: _BadgeIcons(card),
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (context) => _ItemDetails(card),
                            ),
                          ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// The memory state in words, for the curriculum list.
String memoryLabel(StudyCard card, DateTime now) {
  final state = card.state;
  final importance = switch (card.mapping.importance) {
    'core' => 'Core',
    'secondary' => 'Secondary',
    _ => 'Tertiary',
  };
  if (state == null) return '$importance · New';
  final recall = 'recall ${(card.retrievability * 100).round()} %';
  if (card.isOnLearningStep) return '$importance · Learning';
  if (card.isDue(now)) return '$importance · Due now · $recall';
  final days = (state.due.difference(now).inHours / 24).ceil();
  final when = days <= 1 ? 'within a day' : 'in $days days';
  return '$importance · Next review $when · $recall';
}

class _BadgeIcons extends StatelessWidget {
  const _BadgeIcons(this.card);

  final StudyCard card;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.isUnverified)
          const Tooltip(
            message: 'Unverified',
            child: Icon(Icons.pending_outlined, size: 20),
          ),
        if (card.isStale)
          const Tooltip(
            message: 'May be out of date',
            child: Icon(Icons.update, size: 20),
          ),
      ],
    );
  }
}

class _ItemDetails extends ConsumerWidget {
  const _ItemDetails(this.card);

  final StudyCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = card.state;
    final sources = ref.watch(itemSourcesProvider(card.itemId));
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(card.item.assertionText, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(
                label: Text(
                  '${card.mapping.importance} · ${card.mapping.certificationId}',
                ),
              ),
              if (card.isUnverified) const Chip(label: Text('Unverified')),
              if (card.isStale) const Chip(label: Text('May be out of date')),
            ],
          ),
          const SizedBox(height: 12),
          if (state == null)
            const Text('Not studied yet.')
          else
            Text(
              'Difficulty ${state.difficulty.toStringAsFixed(1)} of 10 · '
              'stability ${state.stability.toStringAsFixed(1)} days · '
              'recall ${(card.retrievability * 100).round()} % · '
              '${state.reps} reviews, ${state.lapses} lapses',
            ),
          const SizedBox(height: 16),
          Text('Sources', style: theme.textTheme.titleSmall),
          ...switch (sources) {
            AsyncData(value: final sources) => [
              for (final source in sources)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(source.citation.title),
                  subtitle: Text(
                    [source.citation.publisher, ?source.locator].join(' · '),
                  ),
                ),
            ],
            _ => [const LinearProgressIndicator()],
          },
        ],
      ),
    );
  }
}

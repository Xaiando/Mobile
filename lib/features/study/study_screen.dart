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
    // These cards already belong to the active certification. Keeping the
    // timeline within that set preserves the existing track progress totals.
    final historyCards = widget.cards
        .where((card) => _isWineHistoryItem(card.itemId))
        .toList();
    final filtered = _search.text.isNotEmpty || selectedDomain != null;
    return Column(
      children: [
        if (historyCards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('study-wine-history-open'),
                icon: const Icon(Icons.history_edu_outlined),
                label: Text(
                  'Wine history timeline · ${historyCards.length} facts',
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        _WineHistoryTimelineScreen(cards: historyCards),
                  ),
                ),
              ),
            ),
          ),
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

bool _isWineHistoryItem(String id) =>
    id.startsWith('ki_hist_') ||
    id.startsWith('ki_hcourse_') ||
    id.startsWith('ki_htime_');

/// Milestones group related source-cited assertions without introducing new
/// completion requirements. Each lesson still opens its normal source sheet.
class _WineHistoryMoment {
  const _WineHistoryMoment(this.id, this.date, this.title, this.identifiers);

  final String id;
  final String date;
  final String title;
  final List<String> identifiers;
}

const _wineHistoryMoments = <_WineHistoryMoment>[
  _WineHistoryMoment(
    'early-evidence',
    'c. 6000–4000 BCE',
    'Earliest evidence and Areni-1',
    [
      'ki_hist_georgia_wine',
      'ki_hist_areni_cave',
      'n_hcourse_evidence',
      'n_hcourse_case_oldest',
    ],
  ),
  _WineHistoryMoment('roman', 'Roman era', 'Vineyards and wine trade', [
    'ki_hist_pliny_falernian',
    'n_hcourse_rome',
    'n_htime_roman_trade',
  ]),
  _WineHistoryMoment(
    'medieval-burgundy',
    'High Middle Ages',
    'Monastic Burgundy and the Climats',
    ['n_htime_burgundy_medieval'],
  ),
  _WineHistoryMoment('aquitaine', '1152', 'Aquitaine and English trade', [
    'n_htime_aquitaine',
  ]),
  _WineHistoryMoment('gamay', '1395', 'Burgundy’s Gamay restriction', [
    'n_htime_ducal_rule',
  ]),
  _WineHistoryMoment(
    'colonial-americas',
    'Sixteenth century',
    'Wine crosses to South America',
    ['ki_htime_south_america_colonial'],
  ),
  _WineHistoryMoment('glass', '1650s', 'English glass wine bottles', [
    'ki_htime_vessels_glass1650',
    'n_htime_case_vessel_story',
  ]),
  _WineHistoryMoment('cape', '1652–1659', 'The Cape wine settlement', [
    'n_htime_cape',
  ]),
  _WineHistoryMoment('sparkling', '1662', 'Merrett and sparkling wine', [
    'ki_hist_merret_1662',
    'ki_hist_perignon_myth',
    'n_hcourse_sparkling',
    'n_hcourse_case_bubble',
  ]),
  _WineHistoryMoment('methuen', '1703', 'The Methuen trade treaty', [
    'ki_hist_methuen_1703',
    'ki_hcourse_commerce_duty',
  ]),
  _WineHistoryMoment('cork', '1730', 'A surviving corked bottle', [
    'ki_htime_vessels_cork1730',
  ]),
  _WineHistoryMoment('douro', '1756', 'The Douro charter', [
    'ki_hist_douro_1756',
    'ki_hcourse_commerce_charter',
    'n_hcourse_case_boundary',
  ]),
  _WineHistoryMoment('australia-first', '1788', 'The First Fleet vines', [
    'ki_htime_australia_origins_first1788',
  ]),
  _WineHistoryMoment(
    'revolution',
    '1789 onward',
    'Revolution and vineyard ownership',
    ['n_htime_revolution'],
  ),
  _WineHistoryMoment('napoleon-i', '1806', 'Napoleon I and the blockade', [
    'ki_hist_berlin_1806',
    'ki_hcourse_names_blockade',
    'ki_hcourse_names_age',
    'n_hcourse_case_napoleon',
  ]),
  _WineHistoryMoment('busby', '1832', 'Busby’s Australian cuttings', [
    'ki_htime_australia_origins_busby1832',
  ]),
  _WineHistoryMoment('malbec', '1853', 'Mendoza and Malbec', [
    'ki_htime_south_america_malbec1853',
  ]),
  _WineHistoryMoment(
    'classification',
    '1855',
    'Napoleon III and the Bordeaux classification',
    ['ki_hist_classement_1855', 'ki_hcourse_names_list'],
  ),
  _WineHistoryMoment(
    'pasteur',
    '1857–1865',
    'Pasteur, fermentation and wine faults',
    ['n_htime_pasteur'],
  ),
  _WineHistoryMoment(
    'phylloxera',
    '1863–1893',
    'Phylloxera and resistant rootstocks',
    [
      'ki_hist_phylloxera_graft',
      'n_hcourse_phylloxera',
      'n_hcourse_case_phylloxera',
    ],
  ),
  _WineHistoryMoment('prohibition', '1920–1933', 'US Prohibition and repeal', [
    'ki_hist_prohibition_18th',
    'ki_hist_repeal_21st',
    'ki_hcourse_modern_ban',
  ]),
  _WineHistoryMoment('aoc', '1935 onward', 'French appellations', [
    'ki_hist_aoc_1935',
    'ki_hcourse_modern_aoc',
  ]),
  _WineHistoryMoment('italy', '1963–2016', 'Italian origin law', [
    'n_hcourse_doc',
    'n_hcourse_case_doc',
    'n_hcourse_case_repeal',
    'n_hcourse_case_letters',
  ]),
  _WineHistoryMoment('cape-wo', '1972–1973', 'Cape Wine of Origin', [
    'ki_htime_modern_origin_cape_wo',
  ]),
  _WineHistoryMoment('paris', '1976', 'The Judgment of Paris', [
    'ki_hist_paris_1976',
    'ki_hcourse_modern_tasting',
  ]),
  _WineHistoryMoment('ava', '1980', 'The first US AVA', [
    'ki_htime_modern_origin_usa_ava',
    'n_htime_case_newworld_names',
  ]),
  _WineHistoryMoment('gi', '2013 onward', 'Modern geographic indications', [
    'ki_hist_eu_wine_definition',
    'ki_htime_modern_origin_australia_gi',
  ]),
  _WineHistoryMoment('chile-oiv', '2024', 'Chile and OIV sustainability work', [
    'ki_htime_present_chile2024',
    'ki_htime_present_oiv2024',
  ]),
  _WineHistoryMoment('oiv-current', '2026', 'The current wine sector', [
    'ki_htime_present_oiv2026',
  ]),
];

class _WineHistoryTimelineScreen extends ConsumerWidget {
  const _WineHistoryTimelineScreen({required this.cards});

  final List<StudyCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = utcNow(ref.watch(clockProvider));
    final usedIds = <String>{};
    final sections = <Widget>[];
    for (final moment in _wineHistoryMoments) {
      final momentCards = cards
          .where(
            (card) =>
                moment.identifiers.contains(card.itemId) ||
                moment.identifiers.contains(card.item.subjectId),
          )
          .toList();
      if (momentCards.isEmpty) continue;
      usedIds.addAll(momentCards.map((card) => card.itemId));
      sections.add(_historySection(context, moment, momentCards, now));
    }
    final remaining = cards
        .where((card) => !usedIds.contains(card.itemId))
        .toList();
    if (remaining.isNotEmpty) {
      sections.add(
        _historySection(
          context,
          const _WineHistoryMoment(
            'additional',
            'More',
            'Additional wine history',
            [],
          ),
          remaining,
          now,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Wine history')),
      body: ListView(
        key: const ValueKey('study-wine-history-timeline'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'From the earliest wine evidence to today · '
              '${cards.length} facts in your study track. '
              'Open a period to study its source-cited lessons.',
            ),
          ),
          ...sections,
        ],
      ),
    );
  }

  Widget _historySection(
    BuildContext context,
    _WineHistoryMoment moment,
    List<StudyCard> momentCards,
    DateTime now,
  ) {
    return Card(
      child: ExpansionTile(
        key: ValueKey('study-history-${moment.id}'),
        title: Text('${moment.date} · ${moment.title}'),
        subtitle: Text('${momentCards.length} facts'),
        children: [
          for (final card in momentCards)
            ListTile(
              title: Text(
                card.item.assertionText,
                maxLines: 3,
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
      ),
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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';

import '../../core/curriculum/name_normalizer.dart';
import '../../core/questions/exercise.dart';
import '../../core/questions/exercise_presenter.dart';
import '../../core/questions/formats/map/map_exercise.dart';
import '../../core/questions/question_presenter.dart';
import '../../core/study/study_explorer.dart';
import '../../core/study/study_explorer_providers.dart';
import '../../core/study/study_planner.dart';
import '../map/map_presentation.dart';
import '../practice/formats/map_question.dart';
import 'study_screen.dart';

String categoryLabel(StudyCategory category) => switch (category) {
  StudyCategory.grapes => '30 core grapes',
  StudyCategory.history => 'Wine history',
  StudyCategory.regions => 'Regions · WSET 1–2',
  StudyCategory.wines => 'Wines and styles · WSET 1–2',
};

IconData _icon(StudyCategory category) => switch (category) {
  StudyCategory.grapes => Icons.grain,
  StudyCategory.history => Icons.history_edu_outlined,
  StudyCategory.regions => Icons.map_outlined,
  StudyCategory.wines => Icons.wine_bar_outlined,
};

/// Four entrances into the existing curriculum, independent of the selected
/// review track. Routes preserve the Study tab and support direct links.
class StudyExplorerScreen extends ConsumerStatefulWidget {
  const StudyExplorerScreen({super.key, this.category});
  final String? category;

  @override
  ConsumerState<StudyExplorerScreen> createState() =>
      _StudyExplorerScreenState();
}

class _StudyExplorerScreenState extends ConsumerState<StudyExplorerScreen> {
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = StudyCategory.values
        .where((c) => c.name == widget.category)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          category == null ? 'Explore study' : categoryLabel(category),
        ),
      ),
      body: switch (ref.watch(studyTopicsProvider)) {
        AsyncData(:final value) => _content(value, category),
        AsyncError() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Study topics could not be loaded.'),
              TextButton(
                onPressed: () => ref.invalidate(studyTopicsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _content(List<StudyTopic> topics, StudyCategory? category) {
    if (widget.category != null && category == null) {
      return const Center(child: Text('This study category does not exist.'));
    }
    if (category == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Drill into a grape, a place, a wine or a moment in history.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Facts, flashcards, maps and questions. Exploration does not '
            'record reviews or change your study track.',
          ),
          const SizedBox(height: 16),
          for (final c in StudyCategory.values)
            Card(
              child: ListTile(
                key: ValueKey('explore-${c.name}'),
                leading: Icon(_icon(c)),
                title: Text(categoryLabel(c)),
                subtitle: Text(
                  '${topics.where((t) => t.category == c).length} topics',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/study/explore/${c.name}'),
              ),
            ),
        ],
      );
    }
    final visible = topics
        .where((t) => t.category == category && t.matches(_query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const ValueKey('explore-search'),
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search topics and synonyms',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No topics match this search.'))
              : ListView.builder(
                  key: const ValueKey('explore-topics'),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final topic = visible[index];
                    return ListTile(
                      key: ValueKey('explore-topic-${topic.id}'),
                      title: Text(topic.title),
                      subtitle: Text(
                        '${topic.subtitle}\n${topic.cards.length} facts · '
                        '${topic.mapCards.length} map facts',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        '/study/explore/${category.name}/${topic.id}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class StudyTopicScreen extends ConsumerWidget {
  const StudyTopicScreen({
    super.key,
    required this.category,
    required this.topicId,
  });
  final String category;
  final String topicId;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(studyTopicsProvider)) {
        AsyncData(:final value) => _topic(context, value),
        AsyncError() => Scaffold(
          appBar: AppBar(title: const Text('Study topic')),
          body: Center(
            child: TextButton(
              onPressed: () => ref.invalidate(studyTopicsProvider),
              child: const Text('Topic could not be loaded. Retry'),
            ),
          ),
        ),
        _ => Scaffold(
          appBar: AppBar(title: const Text('Study topic')),
          body: const Center(child: CircularProgressIndicator()),
        ),
      };

  Widget _topic(BuildContext context, List<StudyTopic> topics) {
    final topic = topics
        .where((t) => t.id == topicId && t.category.name == category)
        .firstOrNull;
    if (topic == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Study topic')),
        body: const Center(
          child: Text('This study topic is no longer available.'),
        ),
      );
    }
    final related = topics
        .where(
          (t) =>
              t.id != topic.id &&
              t.nodeId != null &&
              (t.nodeId == topic.nodeId ||
                  topic.cards.any(
                    (c) =>
                        c.item.subjectId == t.nodeId ||
                        c.item.objectId == t.nodeId,
                  )),
        )
        .toList();
    return DefaultTabController(
      key: ValueKey('explore-tabs-${topic.id}'),
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(topic.title),
          bottom: const TabBar(
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(text: 'Facts'),
              Tab(text: 'Flashcards'),
              Tab(text: 'Maps'),
              Tab(text: 'Questions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(topic.subtitle),
                if (topic.aliases.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Also known as: ${topic.aliases.join(', ')}'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Source-cited study material; expert verification is shown on each fact.',
                ),
                if (related.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ExpansionTile(
                      title: Text(
                        'Related grapes and places · ${related.length}',
                      ),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final other in related)
                              ActionChip(
                                label: Text(
                                  '${other.title} · ${other.category.name}',
                                ),
                                onPressed: () => context.push(
                                  '/study/explore/${other.category.name}/${other.id}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                for (final card in topic.cards)
                  Card(
                    child: ListTile(
                      key: ValueKey('explore-fact-${card.itemId}'),
                      title: Text(card.item.assertionText),
                      subtitle: Text(
                        '${card.mapping.certificationId}'
                        '${card.isUnverified ? ' · Unverified' : ''}'
                        '${card.isStale ? ' · May be out of date' : ''}',
                      ),
                      trailing: const Icon(Icons.info_outline),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => StudyItemDetails(card),
                      ),
                    ),
                  ),
              ],
            ),
            _TopicDrill(
              key: ValueKey('${topic.id}-flashcards'),
              topic: topic,
              mode: _DrillMode.flashcards,
            ),
            _TopicDrill(
              key: ValueKey('${topic.id}-maps'),
              topic: topic,
              mode: _DrillMode.maps,
            ),
            _TopicDrill(
              key: ValueKey('${topic.id}-questions'),
              topic: topic,
              mode: _DrillMode.questions,
            ),
          ],
        ),
      ),
    );
  }
}

enum _DrillMode { flashcards, maps, questions }

typedef _Drill = ({StudyCard card, QuestionFormat format});

class _TopicDrill extends ConsumerStatefulWidget {
  const _TopicDrill({super.key, required this.topic, required this.mode});
  final StudyTopic topic;
  final _DrillMode mode;
  @override
  ConsumerState<_TopicDrill> createState() => _TopicDrillState();
}

class _TopicDrillState extends ConsumerState<_TopicDrill> {
  late final List<_Drill> _drills;
  final _answer = TextEditingController();
  int _index = 0;
  int _request = 0;
  Exercise? _exercise;
  bool _failed = false;
  bool _revealed = false;
  bool _list = false;
  String? _feedback;
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _drills = [];
    final cards = widget.mode == _DrillMode.maps
        ? widget.topic.mapCards
        : widget.topic.cards;
    for (final card in cards) {
      final formats = card.formats
          .where(
            (f) => switch (widget.mode) {
              _DrillMode.maps => f.mode == 'map_locate',
              _DrillMode.questions => const {
                'mcq',
                'authored_choice',
                'typed',
              }.contains(f.mode),
              _DrillMode.flashcards => const {
                'flashcard',
                'typed',
                'mcq',
                'authored_choice',
              }.contains(f.mode),
            },
          )
          .toList();
      if (widget.mode == _DrillMode.flashcards) {
        formats.sort((a, b) => _flashRank(a).compareTo(_flashRank(b)));
        if (formats.isNotEmpty) {
          _drills.add((card: card, format: formats.first));
        }
      } else {
        for (final format in formats) {
          _drills.add((card: card, format: format));
        }
      }
    }
    _drills.shuffle(Random());
    if (widget.topic.category == StudyCategory.grapes) {
      // Keep the shuffled foundation deck ahead of deeper reference facts.
      final foundation = _drills
          .where((d) => widget.topic.foundationItemIds.contains(d.card.itemId))
          .toList();
      final deeper = _drills
          .where((d) => !widget.topic.foundationItemIds.contains(d.card.itemId))
          .toList();
      _drills
        ..clear()
        ..addAll([...foundation, ...deeper]);
    }
    if (_drills.isNotEmpty) _load();
  }

  int _flashRank(QuestionFormat format) => format.mode == 'flashcard'
      ? 0
      : format.mode == 'typed'
      ? 1
      : 2;

  Future<void> _load() async {
    final request = ++_request;
    _exercise = null;
    _failed = false;
    _revealed = false;
    _feedback = null;
    _chosen = null;
    _list = false;
    _answer.clear();
    try {
      final drill = _drills[_index];
      final exercise = await ref
          .read(studyExplorerProvider)
          .present(
            widget.topic,
            drill.card,
            drill.format,
            seed: ExercisePresenter.newSeed(),
          );
      if (mounted && request == _request) {
        setState(
          () => _exercise = exercise is MapExercise
              ? exercise.inMode(MapMode.outline)
              : exercise,
        );
      }
    } on Object {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  void _submit(Object answer) {
    if (_feedback != null) return;
    final grades = ref.read(studyExplorerProvider).grade(_exercise!, answer);
    final rating = grades.single.rating;
    setState(() {
      _feedback = rating == fsrs.Rating.good || rating == fsrs.Rating.easy
          ? 'Correct'
          : rating == fsrs.Rating.hard
          ? 'Close — check the answer'
          : 'Review the answer';
      _revealed = true;
      if (answer is MapLocateAnswer) _chosen = answer.nodeId;
    });
  }

  @override
  void dispose() {
    _request++;
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_drills.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No exercises of this kind are available for this topic. '
            'The Facts tab still shows its source-cited material.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final exercise = _exercise;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Explore only · no review or completion credit'),
        if (widget.topic.category == StudyCategory.grapes)
          Text(
            widget.topic.foundationItemIds.contains(_drills[_index].card.itemId)
                ? 'WSET Levels 1–2 foundation'
                : 'Deeper sommelier reference',
          ),
        Text(
          '${_index + 1} of ${_drills.length}',
          key: const ValueKey('explore-drill-count'),
        ),
        const SizedBox(height: 16),
        if (_failed) ...[
          const Text('This exercise could not be loaded.'),
          TextButton(
            onPressed: _load,
            child: const Text('Retry this exercise'),
          ),
        ] else if (exercise == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          Text(
            exercise.prompt,
            key: const ValueKey('explore-prompt'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (exercise is MapExercise)
            ..._map(exercise)
          else if (exercise is PresentedQuestion)
            ..._question(exercise),
          if (_feedback != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_feedback!, key: const ValueKey('explore-feedback')),
            ),
          if (_revealed) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  exercise is PresentedQuestion
                      ? exercise.explanation
                      : (exercise as MapExercise).explanation,
                  key: const ValueKey('explore-explanation'),
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('Fact and sources'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => StudyItemDetails(_drills[_index].card),
              ),
            ),
            FilledButton(
              key: const ValueKey('explore-next'),
              onPressed: () {
                setState(() => _index = (_index + 1) % _drills.length);
                _load();
              },
              child: Text(
                _index + 1 == _drills.length ? 'Start again' : 'Next',
              ),
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _question(PresentedQuestion exercise) {
    if (widget.mode == _DrillMode.flashcards) {
      return [
        if (!_revealed)
          FilledButton(
            key: const ValueKey('explore-reveal'),
            onPressed: () => setState(() => _revealed = true),
            child: const Text('Show answer'),
          )
        else
          Text(
            exercise.answer.name,
            key: const ValueKey('explore-answer'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
      ];
    }
    if (exercise.isMultipleChoice) {
      return [
        for (final option in exercise.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: ValueKey('explore-option-${option.nodeId}'),
              onPressed: _revealed ? null : () => _submit(option),
              child: Text(option.name),
            ),
          ),
        if (_revealed) Text('Answer: ${exercise.answer.name}'),
      ];
    }
    return [
      TextField(
        key: const ValueKey('explore-typed-answer'),
        controller: _answer,
        enabled: !_revealed,
        decoration: const InputDecoration(
          labelText: 'Your answer',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (text) {
          if (!_revealed) _submit(text);
        },
      ),
      if (!_revealed)
        FilledButton(
          onPressed: () => _submit(_answer.text),
          child: const Text('Check answer'),
        )
      else
        Text('Answer: ${exercise.answer.name}'),
    ];
  }

  List<Widget> _map(MapExercise exercise) => [
    SizedBox(
      height: 360,
      child: MapQuestionMap(
        exercise: exercise,
        revealed: _revealed,
        highlights: {
          if (_revealed) exercise.nodeId: MapHighlight.correct,
          if (_revealed &&
              _chosen != null &&
              !exercise.correctNodeIds.contains(_chosen))
            _chosen!: MapHighlight.incorrect,
        },
        onTap: _revealed
            ? null
            : (tap) => _submit(
                MapLocateAnswer.fromTap(tap, preferredNodeId: exercise.nodeId),
              ),
      ),
    ),
    if (!_revealed)
      TextButton.icon(
        icon: const Icon(Icons.list),
        label: Text(_list ? 'Hide location list' : 'Answer from a list'),
        onPressed: () => setState(() => _list = !_list),
      ),
    if (_list && !_revealed)
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry
              in (exercise.names.entries.toList()..sort(
                (a, b) =>
                    normalizeName(a.value).compareTo(normalizeName(b.value)),
              )))
            OutlinedButton(
              key: ValueKey('explore-map-${entry.key}'),
              child: Text(
                entry.value,
                semanticsLabel: 'Select location ${entry.value}',
              ),
              onPressed: () => _submit(MapLocateAnswer.fromList(entry.key)),
            ),
        ],
      ),
    if (_revealed) Text('Location: ${exercise.nodeName}'),
  ];
}

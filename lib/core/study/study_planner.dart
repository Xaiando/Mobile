import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import '../time/utc_clock.dart';
import 'memory_state.dart';
import '../journal/wine_journal.dart';
import 'priority.dart';
import 'scheduler_config.dart';

/// An item's mapping to the active track: the nearest mapping along the
/// track's inheritance chain, the track itself first (audit CM-3).
class EffectiveMapping {
  const EffectiveMapping({
    required this.knowledgeItemId,
    required this.certificationId,
    required this.importance,
    required this.minimumDepth,
    required this.chainDepth,
  });

  final String knowledgeItemId;

  /// The certification that holds the mapping: the track, or a level it
  /// includes.
  final String certificationId;

  /// `core`, `secondary` or `tertiary`.
  final String importance;

  /// 1 recognize, 2 also forward recall, 3 also reverse recall (CM-6).
  final int minimumDepth;

  /// 0 when the track maps the item itself, 1 for the level below, and so on.
  final int chainDepth;

  double get relevance => relevanceOf(importance);
}

/// A question format: a template's direction and mode (audit QG-1).
class QuestionFormat {
  const QuestionFormat({
    required this.questionTemplateId,
    required this.direction,
    required this.mode,
  });

  final String questionTemplateId;

  /// `forward` or `reverse`.
  final String direction;

  /// `mcq` or `flashcard`.
  final String mode;

  bool get isReverse => direction == 'reverse';
  bool get isMultipleChoice => mode == 'mcq';

  /// The `minimum_depth` at which a track serves this format (CM-6).
  int get requiredDepth => isReverse ? 3 : (isMultipleChoice ? 1 : 2);

  /// Easiest first: recognition before recall, forward before reverse.
  int get difficultyRank => (isReverse ? 2 : 0) + (isMultipleChoice ? 0 : 1);

  @override
  String toString() => questionTemplateId;
}

/// One item the learner can study on the active track, with its memory
/// state and priority.
class StudyCard {
  const StudyCard({
    required this.item,
    required this.mapping,
    required this.formats,
    required this.state,
    required this.retrievability,
    required this.priority,
    required this.isStale,
    this.journalFactor = 1,
  });

  final KnowledgeItem item;
  final EffectiveMapping mapping;

  /// The formats the track serves for this item, easiest first; never empty.
  final List<QuestionFormat> formats;

  /// Null while the item is new (FS-3).
  final ReviewState? state;

  /// R now, from the package; 0 for a new item.
  final double retrievability;

  /// Null for a new item: new items come from their own budget (A-2).
  final Priority? priority;

  /// Not verified for [stalenessMonths] months: "may be out of date" (V-4).
  final bool isStale;

  /// J (A-5): above 1 when the journal holds a wine the item is about. It
  /// is part of [priority], and it also orders new items.
  final double journalFactor;

  String get itemId => item.id;
  bool get isNew => state == null;
  bool get isUnverified => item.verificationStatus == 'unverified';
  bool get isOnLearningStep => state != null && isOnStep(state!);

  bool isDue(DateTime now) => state != null && !state!.due.isAfter(now);

  /// This card after a review in the current session.
  StudyCard reviewed(ReviewState after) => StudyCard(
    item: item,
    mapping: mapping,
    formats: formats,
    state: after,
    retrievability: 1,
    priority: priority,
    isStale: isStale,
    journalFactor: journalFactor,
  );

  /// The format to present: a new item starts with its easiest format;
  /// later presentations vary it, since every format updates the same
  /// memory state (FS-2).
  QuestionFormat chooseFormat(Random random) =>
      isNew ? formats.first : formats[random.nextInt(formats.length)];

  @override
  String toString() => '$itemId ${priority ?? '(new)'}';
}

/// The items of one study session, in the order to study them.
class StudyPlan {
  const StudyPlan({
    required this.certificationId,
    required this.cards,
    required this.dueCount,
    required this.newAvailable,
  });

  final String certificationId;
  final List<StudyCard> cards;

  /// Items due now on this track, including any the session had no room for.
  final int dueCount;

  /// New items the track could introduce, including those not planned.
  final int newAvailable;
}

/// The Home dashboard's summary of the active track (spec TASK-006).
class StudyOverview {
  const StudyOverview({
    required this.certification,
    required this.dueCount,
    required this.newAvailable,
    required this.studied,
    required this.total,
    required this.retention,
    required this.changed,
  });

  final Certification certification;
  final int dueCount;
  final int newAvailable;

  /// Items on the track with a memory state.
  final int studied;

  /// Items the track serves today.
  final int total;

  /// The share of reviews of items in Review state answered correctly in
  /// the last [StudyPlanner.retentionWindow]; null without such reviews.
  final double? retention;

  /// Studied items whose fact changed or ended (audit V-3).
  final List<ExpiredItem> changed;
}

/// Builds study sessions (spec §G, TASK-005): due items by priority, then a
/// budget of new items.
///
/// SQL selects the candidates; retrievability comes from the `fsrs`
/// package and the score is computed in Dart (A-6).
class StudyPlanner {
  StudyPlanner(this.db, {Clock? clock, this.weights = const PriorityWeights()})
    : _clock = clock ?? const Clock(),
      _graph = KnowledgeGraph(db, clock: clock);

  final AppDatabase db;
  final PriorityWeights weights;
  final Clock _clock;
  final KnowledgeGraph _graph;

  static const retentionWindow = Duration(days: 30);

  /// The effective mapping of every item the track covers (CM-3). Items
  /// without one are not studied on this track (CM-4).
  Future<Map<String, EffectiveMapping>> effectiveMappings(
    String certificationId,
  ) async {
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE chain(id, depth) AS (
        SELECT ?1, 0
        UNION ALL
        SELECT c.includes_certification_id, chain.depth + 1
        FROM certifications c JOIN chain ON c.id = chain.id
        WHERE c.includes_certification_id IS NOT NULL
          AND chain.depth < ${KnowledgeGraph.maxDepth}
      )
      SELECT m.knowledge_item_id, m.certification_id, m.importance,
             m.minimum_depth, chain.depth AS chain_depth
      FROM certification_knowledge_mappings m
      JOIN chain ON chain.id = m.certification_id
      ORDER BY m.knowledge_item_id, chain.depth''',
          variables: [Variable(certificationId)],
          readsFrom: {db.certifications, db.certificationKnowledgeMappings},
        )
        .get();
    final mappings = <String, EffectiveMapping>{};
    for (final row in rows) {
      final itemId = row.read<String>('knowledge_item_id');
      // Rows arrive nearest first; the first mapping of an item wins.
      mappings.putIfAbsent(
        itemId,
        () => EffectiveMapping(
          knowledgeItemId: itemId,
          certificationId: row.read<String>('certification_id'),
          importance: row.read<String>('importance'),
          minimumDepth: row.read<int>('minimum_depth'),
          chainDepth: row.read<int>('chain_depth'),
        ),
      );
    }
    return mappings;
  }

  /// Every item the track serves today, with its memory state and priority.
  ///
  /// An item qualifies when its relation is in force, no item supersedes it
  /// (FS-13), the track maps it (CM-4), and a question exists for it.
  Future<List<StudyCard>> cards(String certificationId) async {
    final now = utcNow(_clock);
    final today = localToday(_clock);
    final mappings = await effectiveMappings(certificationId);
    final items = await _graph.currentItems(on: today);
    final formats = await _formatsByItem();
    final states = {
      for (final state in await db.select(db.reviewStates).get())
        state.knowledgeItemId: state,
    };
    final scheduler = await _scheduler();
    final staleCutoff = staleBefore(now);
    final lastMet = await WineJournal(db).lastMetByNode();
    final todayUtc = DateTime.parse('${today}T00:00:00Z');

    /// J for [item]: from the most recent wine about its subject or object.
    double journal(KnowledgeItem item) {
      final days = [
        for (final node in [item.subjectId, item.objectId])
          if (lastMet[node] case final day?)
            todayUtc.difference(DateTime.parse('${day}T00:00:00Z')).inDays,
      ];
      return journalFactor(
        days.isEmpty ? null : days.reduce(min),
        weights: weights,
      );
    }

    double retrievability(ReviewState? state) =>
        state == null ? 0 : retrievabilityOf(state, scheduler, now);

    // A-4, with one refinement: an item on a relearning step was just
    // forgotten, but the package reports R = 1 until a whole day has passed.
    // It counts as fully forgotten until it graduates again (A-8).
    double weakness(ReviewState state) =>
        state.state == fsrs.State.relearning.value
        ? 1
        : 1 - retrievability(state);

    final dependents = <String, List<({int depth, double weakness})>>{};
    for (final pair in await _graph.prerequisiteClosure()) {
      final state = states[pair.dependent];
      if (state == null) continue; // only reviewed dependents count
      dependents.putIfAbsent(pair.prerequisite, () => []).add((
        depth: pair.depth,
        weakness: weakness(state),
      ));
    }

    final cards = <StudyCard>[];
    for (final item in items) {
      final mapping = mappings[item.id];
      final available = formats[item.id];
      if (mapping == null || available == null) continue;
      final state = states[item.id];
      final r = retrievability(state);
      final j = journal(item);
      cards.add(
        StudyCard(
          item: item,
          mapping: mapping,
          formats: servedFormats(available, mapping.minimumDepth),
          state: state,
          retrievability: r,
          priority: state == null
              ? null
              : Priority.of(
                  retrievability: r,
                  relevance: mapping.relevance,
                  lapses: state.lapses,
                  prerequisiteFactor: prerequisiteFactor(
                    dependents[item.id] ?? const [],
                    weights: weights,
                  ),
                  journalFactor: j,
                  weights: weights,
                ),
          isStale: item.lastVerifiedAt.isBefore(staleCutoff),
          journalFactor: j,
        ),
      );
    }
    return cards;
  }

  /// Plans a session for the active track, or [certificationId].
  ///
  /// Up to [sessionSize] items (15 by default): first the items whose
  /// learning step is due, then due reviews by priority, then at most
  /// [newItems] new items (5 by default), prerequisites and core items
  /// first (TASK-005, A-2, P-4). Returns null without a track.
  Future<StudyPlan?> plan({
    String? certificationId,
    int? sessionSize,
    int? newItems,
  }) async {
    final profile = await _profile();
    final track = certificationId ?? profile?.activeCertificationId;
    if (track == null) return null;
    return _planFrom(
      track,
      await cards(track),
      sessionSize: sessionSize ?? profile?.sessionSize ?? 15,
      newItems: newItems ?? profile?.newItemsPerSession ?? 5,
    );
  }

  Future<StudyPlan> _planFrom(
    String track,
    List<StudyCard> all, {
    required int sessionSize,
    required int newItems,
  }) async {
    final now = utcNow(_clock);
    final due = orderDue(all.where((c) => c.isDue(now)));
    final fresh = all.where((c) => c.isNew).toList();
    return StudyPlan(
      certificationId: track,
      cards: [
        ...due.take(sessionSize),
        ...orderNew(
          fresh,
          await _directPrerequisites(),
          limit: min(newItems, max(0, sessionSize - due.length)),
        ),
      ],
      dueCount: due.length,
      newAvailable: fresh.length,
    );
  }

  /// Due items in session order: learning steps first, oldest due first,
  /// because the package's whole-day R cannot rank them (A-9); then reviews
  /// by descending priority score (A-2).
  static List<StudyCard> orderDue(Iterable<StudyCard> due) {
    int byDue(StudyCard a, StudyCard b) {
      final order = a.state!.due.compareTo(b.state!.due);
      return order != 0 ? order : a.itemId.compareTo(b.itemId);
    }

    final steps = due.where((c) => c.isOnLearningStep).toList()..sort(byDue);
    final reviews = due.where((c) => !c.isOnLearningStep).toList()
      ..sort((a, b) {
        final order = b.priority!.score.compareTo(a.priority!.score);
        return order != 0 ? order : byDue(a, b);
      });
    return [...steps, ...reviews];
  }

  /// New items in the order to introduce them: an item never comes before a
  /// new prerequisite of its own; among the items ready, by relevance times
  /// the journal factor (core first, and a wine just logged lifts its
  /// items), then by ID (A-2, A-5). [prerequisites] maps an item to its
  /// direct prerequisites. Stops after [limit] items when given.
  static List<StudyCard> orderNew(
    List<StudyCard> fresh,
    Map<String, List<String>> prerequisites, {
    int? limit,
  }) {
    final byId = {for (final card in fresh) card.itemId: card};
    int priorityOrder(StudyCard a, StudyCard b) {
      final order = (b.mapping.relevance * b.journalFactor).compareTo(
        a.mapping.relevance * a.journalFactor,
      );
      return order != 0 ? order : a.itemId.compareTo(b.itemId);
    }

    final ordered = <StudyCard>[];
    final remaining = {...byId.keys};
    bool isReady(String id) =>
        (prerequisites[id] ?? const []).every((p) => !remaining.contains(p));
    while (remaining.isNotEmpty && ordered.length < (limit ?? fresh.length)) {
      final ready = [
        for (final id in remaining)
          if (isReady(id)) byId[id]!,
      ];
      // A cycle cannot pass the validator; if one did, fall back to priority.
      final candidates = ready.isNotEmpty
          ? ready
          : [for (final id in remaining) byId[id]!];
      final next = (candidates..sort(priorityOrder)).first;
      ordered.add(next);
      remaining.remove(next.itemId);
    }
    return ordered;
  }

  /// The formats a track serves at [minimumDepth], easiest first (CM-6).
  ///
  /// If none of the item's questions reaches that depth (an MCQ-only depth
  /// on a flashcard-only item), the easiest question is served instead, so
  /// a mapped item is never unreachable (A-10).
  static List<QuestionFormat> servedFormats(
    List<QuestionFormat> available,
    int minimumDepth,
  ) {
    final sorted = [...available]
      ..sort((a, b) => a.difficultyRank.compareTo(b.difficultyRank));
    final served = [
      for (final format in sorted)
        if (format.requiredDepth <= minimumDepth) format,
    ];
    return served.isNotEmpty ? served : [sorted.first];
  }

  /// The overview of the active track, or null before a track is chosen.
  Future<StudyOverview?> overview() async {
    final profile = await _profile();
    if (profile == null) return null;
    final track = profile.activeCertificationId;
    final all = await cards(track);
    final plan = await _planFrom(
      track,
      all,
      sessionSize: profile.sessionSize,
      newItems: profile.newItemsPerSession,
    );
    final studiedIds = {
      for (final state in await db.select(db.reviewStates).get())
        state.knowledgeItemId,
    };
    return StudyOverview(
      certification: await (db.select(
        db.certifications,
      )..where((c) => c.id.equals(track))).getSingle(),
      dueCount: plan.dueCount,
      newAvailable: plan.newAvailable,
      studied: all.where((c) => !c.isNew).length,
      total: all.length,
      retention: await retention(),
      changed: [
        for (final expired in await _graph.expiredItems())
          if (studiedIds.contains(expired.itemId)) expired,
      ],
    );
  }

  /// Recomputes [compute] whenever a review, the profile or the curriculum
  /// changes, so every screen follows the learner's progress.
  Stream<T> watch<T>(Future<T> Function() compute) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.reviewStates,
          db.userProfiles,
          db.curriculumReleases,
          db.questions,
        },
      )
      .watch()
      .asyncMap((_) => compute());

  /// The share of recall attempts on items in Review state that succeeded
  /// in the last [retentionWindow] (FSRS "true retention"); null if there
  /// were none.
  Future<double?> retention() async {
    final since = utcNow(_clock).subtract(retentionWindow);
    final row = await db
        .customSelect(
          '''
      SELECT count(*) AS attempts, total(rating > 1) AS recalled FROM (
        SELECT rating, reviewed_at,
               lag(state_after) OVER (
                 PARTITION BY knowledge_item_id ORDER BY reviewed_at, id
               ) AS state_before
        FROM review_events
      )
      WHERE state_before = 2 AND reviewed_at >= ?1''',
          variables: [Variable(since)],
          readsFrom: {db.reviewEvents},
        )
        .getSingle();
    final attempts = row.read<int>('attempts');
    return attempts == 0 ? null : row.read<double>('recalled') / attempts;
  }

  Future<UserProfile?> _profile() => (db.select(
    db.userProfiles,
  )..where((p) => p.id.equals(1))).getSingleOrNull();

  Future<Map<String, List<String>>> _directPrerequisites() async {
    final prerequisites = <String, List<String>>{};
    for (final edge in await db.select(db.knowledgeItemPrerequisites).get()) {
      prerequisites
          .putIfAbsent(edge.knowledgeItemId, () => [])
          .add(edge.prerequisiteItemId);
    }
    return prerequisites;
  }

  Future<fsrs.Scheduler> _scheduler() async {
    final config = await latestSchedulerConfig(db);
    // Before startup seeds version 1, its values are the package defaults.
    return config == null ? fsrs.Scheduler() : schedulerFor(config);
  }

  Future<Map<String, List<QuestionFormat>>> _formatsByItem() async {
    final rows = await db
        .customSelect(
          '''
      SELECT q.knowledge_item_id, q.question_template_id, t.direction, t.mode
      FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      ORDER BY q.knowledge_item_id, q.question_template_id''',
          readsFrom: {db.questions, db.questionTemplates},
        )
        .get();
    final formats = <String, List<QuestionFormat>>{};
    for (final row in rows) {
      formats
          .putIfAbsent(row.read<String>('knowledge_item_id'), () => [])
          .add(
            QuestionFormat(
              questionTemplateId: row.read<String>('question_template_id'),
              direction: row.read<String>('direction'),
              mode: row.read<String>('mode'),
            ),
          );
    }
    return formats;
  }
}

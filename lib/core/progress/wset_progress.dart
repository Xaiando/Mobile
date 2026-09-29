import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../curriculum/knowledge_graph.dart';
import '../coverage/coverage_formats.dart';
import '../coverage/generated_coverage_formats.dart';
import '../database/app_database.dart';
import '../diploma_tasting/diploma_tasting_evidence.dart';
import '../study/study_planner.dart';
import '../time/utc_clock.dart';
import 'wset_scope.dart';
import 'wset_requirements.dart';
import 'wset_practice_evidence.dart';

/// Counts current, mapped facts. A fact counts once, regardless of formats.
class ProgressCounts {
  const ProgressCounts({
    required this.mapped,
    required this.available,
    required this.studied,
    required this.mastered,
    required this.due,
  });

  final int mapped;
  final int available;
  final int studied;
  final int mastered;
  final int due;

  int get unavailable => mapped - available;
  int get newItems => available - studied;
  double? get studiedFraction => available == 0 ? null : studied / available;
  double? get masteredFraction => available == 0 ? null : mastered / available;
  bool get availableMaterialMastered => available > 0 && mastered == available;
}

/// Question coverage of current, mapped core facts. This is authored app
/// content, independent of the learner's reviews or an official syllabus.
class CorePracticeCoverage {
  const CorePracticeCoverage({required this.core, required this.useful});

  final int core;
  final int useful;

  int get missingUsefulPractice => core - useful;
  bool get complete => core > 0 && missingUsefulPractice == 0;
}

class ProgressTopic {
  const ProgressTopic({required this.title, required this.counts});
  final String title;
  final ProgressCounts counts;
}

class ProgressSuggestion {
  const ProgressSuggestion({
    required this.itemId,
    required this.title,
    required this.topic,
    required this.reason,
  });
  final String itemId;
  final String title;
  final String topic;
  final String reason;
}

class WsetUnitProgress {
  const WsetUnitProgress({
    required this.scope,
    required this.counts,
    this.physicalFlights = 0,
  });
  final WsetUnitScope scope;
  final ProgressCounts counts;

  /// Saved three-actual-wine practice, not a tasting grade or unit pass.
  final int physicalFlights;
}

class WsetRequirementProgress {
  const WsetRequirementProgress({
    required this.requirement,
    required this.counts,
  });
  final WsetRequirement requirement;
  final ProgressCounts counts;

  bool get complete =>
      requirement.reviewed &&
      counts.mapped > 0 &&
      counts.unavailable == 0 &&
      counts.mastered == counts.mapped;
}

class WsetLevelProgress {
  const WsetLevelProgress({
    required this.scope,
    required this.counts,
    required this.selectable,
    required this.examPassed,
    required this.topics,
    required this.nextItems,
    required this.units,
    required this.unassigned,
    this.requiredCounts,
    this.optionalCounts,
    this.corePracticeCoverage,
    this.requirements = const [],
    this.practiceEvidence = const WsetPracticeEvidence(),
  });

  final WsetLevelScope scope;
  final ProgressCounts counts;
  final bool selectable;

  /// Learner-entered exam result; never inferred from app study activity.
  final bool examPassed;
  final List<ProgressTopic> topics;
  final List<ProgressSuggestion> nextItems;
  final List<WsetUnitProgress> units;
  final ProgressCounts unassigned;
  final ProgressCounts? requiredCounts;
  final ProgressCounts? optionalCounts;
  final CorePracticeCoverage? corePracticeCoverage;
  final List<WsetRequirementProgress> requirements;
  final WsetPracticeEvidence practiceEvidence;

  /// Older scope fixtures without a requirement catalog retain their historic
  /// counts. Published Levels 1–3 use an explicit required study denominator.
  ProgressCounts get milestoneCounts => requiredCounts ?? counts;

  /// Personal required-topic and recorded-practice milestone. Other mapped
  /// core material may still need useful question formats.
  bool get appLevelComplete =>
      scope.curriculumComplete &&
      milestoneCounts.mapped > 0 &&
      milestoneCounts.unavailable == 0 &&
      milestoneCounts.mastered == milestoneCounts.mapped &&
      requirements.every((requirement) => requirement.complete) &&
      practiceEvidence.satisfies(scope.practice);
}

class WsetProgressSnapshot {
  const WsetProgressSnapshot({required this.asOf, required this.levels});
  final DateTime asOf;
  final List<WsetLevelProgress> levels;
}

/// Derives study progress from the planner's cumulative mappings and FSRS
/// projection. No new learner schema or separate format-specific counters.
class WsetProgressRepository {
  WsetProgressRepository(
    this.db, {
    required this.scope,
    StudyPlanner? planner,
    Clock? clock,
  }) : _clock = clock ?? const Clock(),
       _planner = planner ?? StudyPlanner(db, clock: clock),
       _graph = KnowledgeGraph(db, clock: clock);

  final AppDatabase db;
  final WsetScope scope;
  final Clock _clock;
  final StudyPlanner _planner;
  final KnowledgeGraph _graph;

  static const masteryStabilityDays = 7.0;
  static const masteryRetrievability = 0.90;
  static const masterySuccessfulDates = 3;
  static const masterySpan = Duration(days: 7);

  /// Recompute after reviews, curriculum changes and learner-entered passes.
  /// Optional clock refreshes reuse the subscription and retain the last value.
  Stream<WsetProgressSnapshot> watch({Duration? refreshInterval}) {
    if (refreshInterval != null && refreshInterval <= Duration.zero) {
      throw ArgumentError.value(refreshInterval, 'refreshInterval');
    }
    final updates = StreamController<WsetProgressSnapshot>();
    StreamSubscription<void>? changes;
    Timer? timer;
    var cancelled = false;
    var computing = false;
    var requested = false;

    Future<void> recompute() async {
      if (cancelled) {
        return;
      }
      requested = true;
      if (computing) {
        return;
      }
      computing = true;
      try {
        // A write during a calculation needs one follow-up, not a parallel
        // query or a queue of obsolete snapshots.
        while (requested && !cancelled) {
          requested = false;
          try {
            final value = await snapshot();
            if (cancelled) {
              return;
            }
            updates.add(value);
            // Start only after initial data. A slow first calculation must
            // never be restarted by a clock tick before it can finish.
            if (timer == null && refreshInterval != null) {
              timer = Timer.periodic(
                refreshInterval,
                (_) => unawaited(recompute()),
              );
            }
          } catch (error, stack) {
            if (!cancelled) {
              updates.addError(error, stack);
            }
          }
        }
      } finally {
        computing = false;
      }
    }

    updates.onListen = () {
      changes = db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.reviewStates,
              db.reviewEvents,
              db.userSettings,
              db.certifications,
              db.certificationKnowledgeMappings,
              db.curriculumReleases,
              db.knowledgeItems,
              db.knowledgeRelations,
              db.knowledgeNodes,
              db.curriculumDomains,
              db.questions,
              db.exercisePools,
              db.exercisePoolItems,
              db.schedulerConfigs,
              db.tastingSessions,
              db.tastingDescriptors,
              db.tastingGrids,
              db.tastingGridAttributes,
              db.tastingGridValues,
            },
          )
          .watch()
          .map<void>((_) {})
          .listen(
            (_) => unawaited(recompute()),
            onError: updates.addError,
            onDone: updates.close,
          );
    };
    updates.onCancel = () async {
      cancelled = true;
      timer?.cancel();
      await changes?.cancel();
    };
    return updates.stream;
  }

  Future<void> setExamPassed(String certificationId, bool passed) async {
    if (!scope.levels.any(
      (level) => level.certificationId == certificationId,
    )) {
      throw ArgumentError.value(certificationId, 'certificationId');
    }
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSettingsCompanion.insert(
            name: _passKey(certificationId),
            value: passed ? 'true' : 'false',
            updatedAt: utcNow(_clock),
          ),
        );
  }

  static String _passKey(String certificationId) =>
      'exam_pass_${certificationId.toLowerCase()}';

  Future<WsetProgressSnapshot> snapshot() async {
    scope.validate();
    final now = utcNow(_clock);
    final items = await _graph.currentItems();
    final generatedFormats = await GeneratedCoverageFormats.read(
      db,
      on: localToday(_clock),
    );
    final certifications = {
      for (final row in await db.select(db.certifications).get()) row.id: row,
    };
    final domains = {
      for (final row in await db.select(db.curriculumDomains).get())
        row.id: row.displayName,
    };
    final nodes = {
      for (final row in await db.select(db.knowledgeNodes).get())
        row.id: row.name,
    };
    final settings = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    final diplomaTasting = DiplomaTastingEvidenceReader.read(
      settings,
      now: now,
    );
    final events = <String, List<ReviewEvent>>{};
    for (final event in await db.select(db.reviewEvents).get()) {
      if (!event.reviewedAt.isAfter(now)) {
        events.putIfAbsent(event.knowledgeItemId, () => []).add(event);
      }
    }
    final regionSets = <String, Set<String>>{};
    final itemQuery = db.selectOnly(db.knowledgeItems)
      ..addColumns([db.knowledgeItems.id]);
    final installedItemIds = {
      for (final row in await itemQuery.get()) row.read(db.knowledgeItems.id)!,
    };
    final installedItems = {
      for (final item in await db.select(db.knowledgeItems).get())
        item.id: item,
    };
    for (final level in scope.levels) {
      for (final requirement in level.requirements) {
        for (final dimension in requirement.dimensions) {
          for (final id in dimension.itemIds) {
            final item = installedItems[id];
            if (item == null) {
              throw FormatException('Unknown requirement item: $id');
            }
            if (dimension.kind != 'location' &&
                item.relationType == 'LOCATED_IN') {
              throw FormatException(
                'A map location cannot explain ${dimension.kind}: $id',
              );
            }
            if (dimension.kind == 'location' &&
                item.relationType != 'LOCATED_IN') {
              throw FormatException(
                'Location evidence must locate a place: $id',
              );
            }
          }
        }
      }
      for (final unit in level.units) {
        for (final id in unit.itemIds) {
          if (!installedItemIds.contains(id)) {
            throw FormatException('Unknown progress topic item: $id');
          }
        }
        for (final root in [...unit.regionRoots, ...unit.geographyRoots]) {
          if (!nodes.containsKey(root)) {
            throw FormatException('Unknown progress topic region: $root');
          }
          if (!regionSets.containsKey(root)) {
            regionSets[root] = {
              root,
              for (final node in await _graph.descendants(root)) node.id,
            };
          }
        }
      }
    }
    final levels = <WsetLevelProgress>[];
    for (final level in scope.levels) {
      final mappings = await _planner.effectiveMappings(level.certificationId);
      final mapped = items
          .where((item) => mappings.containsKey(item.id))
          .toList();
      // The planner applies format registry, depth and current-fact rules.
      final cards = {
        for (final card in await _planner.cards(level.certificationId))
          if (card.formats.isNotEmpty) card.itemId: card,
      };
      final generated = generatedFormats.forMappedItems(mappings);
      final coreItems = mapped.where(
        (item) => mappings[item.id]?.importance == 'core',
      );
      final corePracticeCoverage = CorePracticeCoverage(
        core: coreItems.length,
        useful: coreItems.where((item) {
          final available = generated[item.id] ?? const <QuestionFormat>[];
          final served = StudyPlanner.servedFormats(
            available,
            mappings[item.id]!.minimumDepth,
          );
          return hasUsefulPracticeForModes(served.map((format) => format.mode));
        }).length,
      );
      final mastered = {
        for (final card in cards.values)
          if (_isMastered(card, events[card.itemId] ?? const [], now))
            card.itemId,
      };
      ProgressCounts count(Iterable<KnowledgeItem> subset) {
        final all = subset.toList();
        final served = [
          for (final item in all)
            if (cards[item.id] != null) cards[item.id]!,
        ];
        return ProgressCounts(
          mapped: all.length,
          available: served.length,
          studied: served.where((card) => card.state != null).length,
          mastered: served
              .where((card) => mastered.contains(card.itemId))
              .length,
          due: served.where((card) => card.isDue(now)).length,
        );
      }

      final topicIds = mapped.map((item) => item.domainId).toSet().toList()
        ..sort();
      final topics = [
        for (final domain in topicIds)
          ProgressTopic(
            title: domains[domain] ?? domain,
            counts: count(mapped.where((item) => item.domainId == domain)),
          ),
      ];
      ProgressCounts requirementCount(
        Set<String> ids, {
        WsetRequirement? requirement,
      }) {
        bool serves(String id) {
          final card = cards[id];
          if (card == null) return false;
          if (requirement == null) {
            return level.requirements
                .where((row) => row.itemIds.contains(id))
                .every(
                  (row) => row.dimensions
                      .where((dimension) => dimension.itemIds.contains(id))
                      .every(
                        (dimension) => card.formats.any(
                          (format) => dimension.formats.contains(format.mode),
                        ),
                      ),
                );
          }
          return requirement.dimensions
              .where((dimension) => dimension.itemIds.contains(id))
              .every(
                (dimension) => card.formats.any(
                  (format) => dimension.formats.contains(format.mode),
                ),
              );
        }

        final available = ids.where(serves).toSet();
        return ProgressCounts(
          mapped: ids.length,
          available: available.length,
          studied: available.where((id) => cards[id]!.state != null).length,
          mastered: available.where(mastered.contains).length,
          due: available.where((id) => cards[id]!.isDue(now)).length,
        );
      }

      final requiredIds = level.requiredItemIds;
      final requiredCounts = level.requirements.isEmpty
          ? null
          : requirementCount(requiredIds);
      final candidates =
          cards.values
              .where(
                (card) =>
                    !mastered.contains(card.itemId) &&
                    (level.requirements.isEmpty ||
                        requiredIds.contains(card.itemId)),
              )
              .toList()
            ..sort((a, b) {
              int rank(StudyCard card) => card.isDue(now)
                  ? 0
                  : card.isNew
                  ? 1
                  : 2;
              final rankOrder = rank(a).compareTo(rank(b));
              if (rankOrder != 0) return rankOrder;
              if (a.state != null && b.state != null) {
                final dueOrder = a.state!.due.compareTo(b.state!.due);
                if (dueOrder != 0) return dueOrder;
              }
              return a.itemId.compareTo(b.itemId);
            });
      final assigned = <String, List<KnowledgeItem>>{
        for (final unit in level.units) unit.id: [],
      };
      final unassigned = <KnowledgeItem>[];
      final explicitUnits = {
        for (final unit in level.units)
          for (final id in unit.itemIds) id: unit,
      };
      for (final item in mapped) {
        final regional = level.units
            .where(
              (unit) =>
                  unit.regionRoots.any(
                    (root) => regionSets[root]!.contains(item.subjectId),
                  ) ||
                  (item.relationType == 'LOCATED_IN' &&
                      unit.geographyRoots.any(
                        (root) => regionSets[root]!.contains(item.subjectId),
                      )),
            )
            .firstOrNull;
        final unit =
            explicitUnits[item.id] ??
            regional ??
            level.units
                .where((unit) => unit.domains.contains(item.domainId))
                .firstOrNull;
        if (unit == null) {
          unassigned.add(item);
        } else {
          assigned[unit.id]!.add(item);
        }
      }
      levels.add(
        WsetLevelProgress(
          scope: level,
          counts: count(mapped),
          selectable:
              certifications[level.certificationId]?.isSelectable ?? false,
          examPassed: settings[_passKey(level.certificationId)] == 'true',
          topics: topics,
          nextItems: [
            for (final card in candidates.take(3))
              ProgressSuggestion(
                itemId: card.itemId,
                title: card.item.assertionText,
                topic:
                    '${domains[card.item.domainId] ?? card.item.domainId} · '
                    '${nodes[card.item.subjectId] ?? card.item.subjectId}',
                reason: card.isDue(now)
                    ? 'Review due'
                    : card.isNew
                    ? 'New fact'
                    : 'Keep practising',
              ),
          ],
          units: [
            for (final unit in level.units)
              WsetUnitProgress(
                scope: unit,
                counts: count(assigned[unit.id]!),
                physicalFlights: level.certificationId == 'WSET_L4'
                    ? diplomaTasting.forUnit(unit.id)
                    : 0,
              ),
          ],
          unassigned: count(unassigned),
          requiredCounts: requiredCounts,
          optionalCounts: level.requirements.isEmpty
              ? null
              : count(mapped.where((item) => !requiredIds.contains(item.id))),
          corePracticeCoverage: corePracticeCoverage,
          requirements: List.unmodifiable([
            for (final requirement in level.requirements)
              WsetRequirementProgress(
                requirement: requirement,
                counts: requirementCount(
                  requirement.itemIds,
                  requirement: requirement,
                ),
              ),
          ]),
          practiceEvidence: await WsetPracticeEvidenceReader(db).read(
            int.parse(level.certificationId.substring(6)),
            settings,
            now: now,
            currentItems: items.map((item) => item.id).toSet(),
            mappedItems: mapped.map((item) => item.id).toSet(),
          ),
        ),
      );
    }
    return WsetProgressSnapshot(asOf: now, levels: List.unmodifiable(levels));
  }

  static bool _isMastered(
    StudyCard card,
    List<ReviewEvent> events,
    DateTime now,
  ) {
    final state = card.state;
    if (state == null ||
        state.state != fsrs.State.review.value ||
        state.lastReview.isAfter(now) ||
        state.stability < masteryStabilityDays ||
        card.retrievability < masteryRetrievability) {
      return false;
    }
    DateTime? lastAgain;
    for (final event in events) {
      if (event.rating == fsrs.Rating.again.value &&
          (lastAgain == null || event.reviewedAt.isAfter(lastAgain))) {
        lastAgain = event.reviewedAt;
      }
    }
    // Use distinct UTC review dates, not taps or template counts. Successes
    // at the same instant as a lapse do not restore mastery.
    final dates = <DateTime>{};
    for (final event in events) {
      if (event.rating >= fsrs.Rating.good.value &&
          (lastAgain == null || event.reviewedAt.isAfter(lastAgain))) {
        final date = event.reviewedAt.toUtc();
        dates.add(DateTime.utc(date.year, date.month, date.day));
      }
    }
    if (dates.length < masterySuccessfulDates) return false;
    final ordered = dates.toList()..sort();
    return ordered.last.difference(ordered.first) >= masterySpan;
  }
}

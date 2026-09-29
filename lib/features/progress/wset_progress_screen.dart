import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/progress_state.dart';
import '../../core/progress/progress_providers.dart';
import '../../core/progress/wset_progress.dart';
import '../../core/study/study_providers.dart';
import '../practice/study_session_controller.dart';
import '../diploma_tasting/diploma_tasting_flight_screen.dart';
import '../diploma_written/diploma_written_screen.dart';
import '../diploma_research/diploma_research_screen.dart';
import '../rehearsal/rehearsal_screen.dart';
import '../tasting_guidance/guided_tasting_screen.dart';
import '../tasting_pair/tasting_pair_screen.dart';

class WsetProgressScreen extends ConsumerWidget {
  const WsetProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(wsetProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('WSET progress')),
      body: switch (progress) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Build knowledge that lasts',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Studied means reviewed at least once. Mastered means successful reviews on at least three dates over seven days, with a current memory estimate of at least 90% and seven days of stability. A later wrong answer or fading memory can lower mastery.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Reviews count across question formats and cumulative levels. App milestones describe study material; exam results are recorded separately by you.',
            ),
            const SizedBox(height: 16),
            for (final level in value.levels)
              _LevelSection(
                level,
                value,
                key: ValueKey('wset_progress_${level.scope.certificationId}'),
              ),
          ],
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Progress could not be read: $error'),
                TextButton(
                  onPressed: () => ref.invalidate(wsetProgressProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _LevelSection extends ConsumerStatefulWidget {
  const _LevelSection(this.level, this.snapshot, {super.key});
  final WsetLevelProgress level;
  final WsetProgressSnapshot snapshot;

  @override
  ConsumerState<_LevelSection> createState() => _LevelSectionState();
}

class _LevelSectionState extends ConsumerState<_LevelSection> {
  bool _saving = false;
  bool _starting = false;

  Future<void> _setPass(bool value) async {
    setState(() => _saving = true);
    try {
      final scope = await ref.read(wsetScopeProvider.future);
      await ref
          .read(wsetProgressRepositoryProvider(scope))
          .setExamPassed(widget.level.scope.certificationId, value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The exam status could not be saved. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _study(WsetLevelProgress target, {Set<String>? itemIds}) async {
    setState(() => _starting = true);
    try {
      await ref
          .read(learnerProfilesProvider)
          .selectTrack(target.scope.certificationId);
      final focus =
          itemIds ??
          (target.scope.requirements.isEmpty
              ? null
              : target.scope.requiredItemIds);
      await ref.read(studySessionProvider.notifier).start(itemIds: focus);
      if (mounted) {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go('/practice');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The study session could not start. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _practice(Widget screen) async {
    setState(() => _starting = true);
    try {
      await ref
          .read(learnerProfilesProvider)
          .selectTrack(widget.level.scope.certificationId);
      if (mounted) {
        await Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => screen));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Practice could not open: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final counts = level.milestoneCounts;
    final theme = Theme.of(context);
    final target = level.selectable
        ? level
        : widget.snapshot.levels
              .where(
                (candidate) =>
                    candidate.selectable &&
                    candidate.scope.certificationId.compareTo(
                          level.scope.certificationId,
                        ) >
                        0,
              )
              .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(level.scope.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              level.appLevelComplete
                  ? 'App study milestone complete'
                  : level.scope.curriculumComplete
                  ? 'App study milestone in progress'
                  : 'Full level coverage incomplete',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            if (level.requiredCounts != null) ...[
              const Text('Required study topics'),
              const Text(
                'These bars use the lessons assigned to this level’s study requirements. Optional atlas and extension material are tracked separately.',
              ),
              const SizedBox(height: 8),
            ],
            if (counts.available == 0)
              const Text(
                'Study material not yet available. Progress starts when this level has material to practise.',
              )
            else ...[
              Text(
                '${counts.studied} of ${counts.available} available facts studied',
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: counts.studiedFraction),
              const SizedBox(height: 8),
              Text(
                '${counts.mastered} of ${counts.available} available facts mastered',
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: counts.masteredFraction),
              const SizedBox(height: 8),
              Text('${counts.due} reviews due · ${counts.newItems} new facts'),
              if (counts.availableMaterialMastered)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Available material mastered. Keep reviewing as memory changes.',
                  ),
                ),
            ],
            if (counts.unavailable > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${counts.mapped} facts are mapped to this level; '
                  '${counts.unavailable} cannot yet be practised. They are excluded from the available-material bars and still count as coverage gaps.',
                ),
              ),
            if (level.optionalCounts case final optional?) ...[
              const SizedBox(height: 8),
              Text(
                'Optional material: ${optional.studied}/${optional.available} studied · ${optional.mastered} mastered. It does not block this level’s study milestone.',
              ),
            ],
            if (level.requirements.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Study requirements · ${level.requirements.where((row) => row.complete).length}/${level.requirements.length} mastered',
                ),
                children: [
                  for (final row in level.requirements)
                    ListTile(
                      key: ValueKey(
                        'wset_topic_${level.scope.certificationId}_${row.requirement.id}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.requirement.title),
                      subtitle: Text(
                        '${row.counts.studied}/${row.counts.mapped} studied · ${row.counts.mastered} mastered · ${row.counts.unavailable} unavailable${row.requirement.reviewed ? '' : ' · scope review pending'}',
                      ),
                      leading: Icon(
                        row.complete
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                      ),
                      trailing: row.counts.available > 0 && level.selectable
                          ? const Icon(Icons.play_arrow)
                          : null,
                      onTap:
                          _starting ||
                              !level.selectable ||
                              row.counts.available == 0
                          ? null
                          : () =>
                                _study(level, itemIds: row.requirement.itemIds),
                    ),
                ],
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: level.examPassed,
              onChanged: _saving ? null : (value) => _setPass(value ?? false),
              title: const Text('I have passed this WSET level'),
              subtitle: Text(
                level.examPassed
                    ? 'Exam passed · self-reported. Uncheck to remove.'
                    : 'Self-reported exam result; separate from app progress.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (!level.scope.practice.isEmpty) ...[
              const SizedBox(height: 16),
              Text('Recorded practice', style: theme.textTheme.titleMedium),
              const Text(
                'Participation and saved evidence are separate from fact memory. These activities do not award an official score or pass.',
              ),
              if (level.scope.practice.rehearsal)
                Text(
                  'Complete original rehearsals: ${level.practiceEvidence.rehearsals} · all multiple-choice questions answered',
                ),
              if (level.scope.practice.writtenReview)
                Text(
                  'Written rehearsals reviewed: ${level.practiceEvidence.writtenReviews} · four saved responses and explicit self-review',
                ),
              Text(
                'Distinct calibration cases saved with evidence: ${level.practiceEvidence.calibrationCases}/${level.scope.practice.calibrationCases}',
              ),
              if (level.scope.practice.physicalWines > 0)
                Text(
                  'Physical wines described with evidence: ${level.practiceEvidence.physicalWines}/${level.scope.practice.physicalWines}',
                ),
              if (level.scope.practice.physicalWines == 0 &&
                  !level.scope.practice.pairedTasting)
                Text(
                  'Optional physical wine practice: ${level.practiceEvidence.physicalWines} saved. Fictional calibration cases can complete this app practice requirement.',
                ),
              if (level.scope.practice.pairedTasting)
                Text(
                  'Two-wine practices fully described: ${level.practiceEvidence.pairedTastings} · both wines and their evidence completed',
                ),
              if (level.practiceEvidence.unreadableRecords > 0)
                const Text(
                  'Some saved practice records could not be read. Other valid history remains included.',
                ),
              if (level.selectable)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _starting
                          ? null
                          : () => _practice(
                              RehearsalScreen(
                                initialLevel: int.parse(
                                  level.scope.certificationId.substring(6),
                                ),
                              ),
                            ),
                      child: const Text('Open rehearsal'),
                    ),
                    TextButton(
                      onPressed: _starting
                          ? null
                          : () => _practice(
                              GuidedTastingScreen(
                                initialLevel: int.parse(
                                  level.scope.certificationId.substring(6),
                                ),
                              ),
                            ),
                      child: const Text('Open guided tasting'),
                    ),
                    if (level.scope.practice.pairedTasting)
                      TextButton(
                        onPressed: _starting
                            ? null
                            : () => _practice(const TastingPairScreen()),
                        child: const Text('Open two-wine practice'),
                      ),
                  ],
                ),
            ],
            if (level.nextItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Next to study', style: theme.textTheme.titleMedium),
              for (final item in level.nextItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.reason} · ${item.topic}',
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(item.title),
                    ],
                  ),
                ),
            ],
            if (counts.available > 0 && target != null) ...[
              if (!level.selectable)
                Text(
                  'These facts are included in ${target.scope.title} practice.',
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _starting ? null : () => _study(target),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _starting ? 'Starting…' : 'Study ${target.scope.title}',
                ),
              ),
            ],
            if (level.units.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Diploma unit support', style: theme.textTheme.titleMedium),
              const Text(
                'Topic groups show supporting facts, not unit completion or exam passes. Each fact is assigned to at most one group.',
              ),
              for (final unit in level.units)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('${unit.scope.id} · ${unit.scope.title}'),
                  subtitle: Text(
                    unit.counts.available == 0
                        ? 'Study material not yet available'
                        : '${unit.counts.studied}/${unit.counts.available} studied · '
                              '${unit.counts.mastered}/${unit.counts.available} mastered',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(unit.scope.gap),
                          if (unit.counts.unavailable > 0)
                            Text(
                              '${unit.counts.unavailable} mapped facts are not yet available.',
                            ),
                          if (unit.scope.id == 'D1' ||
                              unit.scope.id == 'D2') ...[
                            const SizedBox(height: 8),
                            Text(
                              'Written practices self-reviewed: ${unit.writtenPractices}. '
                              'These are participation, not examiner marks or unit passes.',
                              key: ValueKey(
                                'wset_unit_written_${unit.scope.id}',
                              ),
                            ),
                            TextButton(
                              key: ValueKey(
                                'wset_unit_written_open_${unit.scope.id}',
                              ),
                              onPressed: _starting || !level.selectable
                                  ? null
                                  : () => _practice(
                                      DiplomaWrittenScreen(
                                        unitId: unit.scope.id,
                                      ),
                                    ),
                              child: Text(
                                'Open ${unit.scope.id} '
                                '${unit.scope.id == 'D1' ? '90' : '60'}-minute writing',
                              ),
                            ),
                          ],
                          if (level.scope.certificationId == 'WSET_L4' &&
                              unit.scope.id == 'D6') ...[
                            const SizedBox(height: 8),
                            Text(
                              unit.researchDraftSaved
                                  ? 'Research workspace: a private draft is saved. This is participation, not an assessed assignment or unit pass.'
                                  : 'Research workspace: no draft saved yet. This does not determine an official D6 result.',
                              key: const ValueKey('wset_unit_research_D6'),
                            ),
                            TextButton(
                              key: const ValueKey('wset_unit_research_open_D6'),
                              onPressed: _starting || !level.selectable
                                  ? null
                                  : () => _practice(
                                      const DiplomaResearchScreen(),
                                    ),
                              child: const Text('Open D6 research workspace'),
                            ),
                          ],
                          if (unit.scope.id == 'D4' ||
                              unit.scope.id == 'D5') ...[
                            const SizedBox(height: 8),
                            Text(
                              'Three-wine physical practices recorded: ${unit.physicalFlights}. '
                              'These are self-reviewed participation, not a tasting score or exam pass.',
                              key: ValueKey(
                                'wset_unit_physical_${unit.scope.id}',
                              ),
                            ),
                            TextButton(
                              key: ValueKey(
                                'wset_unit_physical_open_${unit.scope.id}',
                              ),
                              onPressed: _starting || !level.selectable
                                  ? null
                                  : () => _practice(
                                      DiplomaTastingFlightScreen(
                                        unitId: unit.scope.id,
                                      ),
                                    ),
                              child: Text(
                                'Open ${unit.scope.id} three-wine practice',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              if (level.unassigned.mapped > 0)
                Text(
                  '${level.unassigned.mapped} further mapped facts have no unit topic group yet.',
                ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Coverage and remaining topics'),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final topic in level.topics)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${topic.title}: ${topic.counts.studied}/${topic.counts.available} studied, '
                          '${topic.counts.mastered} mastered, ${topic.counts.unavailable} unavailable.',
                        ),
                      ),
                    for (final gap in level.scope.gaps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(gap),
                      ),
                    const Text(
                      'The official qualification outline informs these coverage notes.',
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: level.scope.sourceUrl),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Official outline link copied.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy official outline link'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

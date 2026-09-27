import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/progress_state.dart';
import '../../core/progress/wset_progress.dart';
import 'wset_progress_screen.dart';

class WsetProgressCard extends ConsumerWidget {
  const WsetProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(wsetProgressProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your WSET progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            switch (progress) {
              AsyncData(:final value) => Column(
                children: [for (final level in value.levels) _LevelRow(level)],
              ),
              AsyncError() => const Text(
                'Progress is temporarily unavailable.',
              ),
              _ => const Text('Calculating your progress…'),
            },
            const SizedBox(height: 8),
            const Text(
              'Counts describe the available study material. Full level coverage is still being built.',
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const WsetProgressScreen()),
              ),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('View WSET progress'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow(this.level);
  final WsetLevelProgress level;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          level.scope.title.replaceFirst('WSET ', ''),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (level.examPassed) const Text('Exam passed · self-reported'),
        Text(
          level.milestoneCounts.available == 0
              ? 'Study material not yet available'
              : '${level.milestoneCounts.studied}/${level.milestoneCounts.available} studied · '
                    '${level.milestoneCounts.mastered}/${level.milestoneCounts.available} mastered',
        ),
        if (level.milestoneCounts.unavailable > 0)
          Text(
            '${level.milestoneCounts.unavailable} required facts are not yet available for practice.',
          ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: level.milestoneCounts.masteredFraction ?? 0,
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/learner_state.dart';
import '../../core/study/study_planner.dart';
import '../practice/study_session_controller.dart';
import 'track_picker.dart';

/// Home: the study dashboard (spec TASK-006).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(studyOverviewProvider);
    final value = overview.value;
    final canStudy = value != null && value.dueCount + value.newAvailable > 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: canStudy
          ? FloatingActionButton.extended(
              onPressed: () {
                ref.read(studySessionProvider.notifier).start();
                context.go('/practice');
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start session'),
            )
          : null,
      body: switch (overview) {
        AsyncData(value: null) => const _Welcome(),
        AsyncData(value: final overview?) => _Dashboard(overview),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Your progress could not be read: $error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.school_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose your certification track',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your study dashboard follows the track you pick. You can '
              'switch at any time without losing progress.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const TrackPicker(),
            const SizedBox(height: 24),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard(this.overview);

  final StudyOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retention = overview.retention;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const Center(child: TrackPicker()),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Stat(
              icon: Icons.schedule,
              label: 'Due now',
              value: '${overview.dueCount}',
            ),
            _Stat(
              icon: Icons.fiber_new_outlined,
              label: 'New available',
              value: '${overview.newAvailable}',
            ),
            _Stat(
              icon: Icons.insights_outlined,
              label: 'Retention (30 days)',
              value: retention == null ? '–' : '${(retention * 100).round()} %',
            ),
            _Stat(
              icon: Icons.checklist,
              label: 'Items studied',
              value: '${overview.studied} of ${overview.total}',
            ),
          ],
        ),
        if (overview.changed.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(
                overview.changed.length == 1
                    ? 'The rules changed for a fact you studied.'
                    : 'The rules changed for ${overview.changed.length} '
                          'facts you studied.',
              ),
              subtitle: const Text(
                'They have left your reviews; your history is kept.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Curriculum content is drafted from public legal texts and is '
          'marked unverified until a qualified reviewer checks it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        const _Disclaimer(),
      ],
    );
  }
}

/// Track names describe what a learner studies for; they claim no
/// affiliation (legal review L-1, audit CM-8).
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Text(
    'WSET and CMS are named only to describe study tracks. This app is not '
    'affiliated with or endorsed by the Wine & Spirit Education Trust or '
    'the Court of Master Sommeliers.',
    style: Theme.of(context).textTheme.bodySmall,
    textAlign: TextAlign.center,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.headlineSmall),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

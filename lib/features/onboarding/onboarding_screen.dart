import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/learner_state.dart';
import '../../core/settings/settings_providers.dart';
import '../home/track_picker.dart';

/// First launch (backlog R1): the age confirmation (legal review L-24), how
/// the app works, and the track choice. It is shown until completed.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _ofAge = false;

  Future<void> _confirmAge() async {
    await ref.read(learnerSettingsProvider).confirmAge();
    setState(() => _step = 1);
  }

  Future<void> _finish() async {
    await ref.read(learnerSettingsProvider).completeOnboarding();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTrack = ref.watch(learnerProfileProvider).value != null;
    final steps = <Widget>[
      _Step(
        icon: Icons.wine_bar,
        title: 'Welcome to Sommelier Study Companion',
        body: const [
          Text(
            'Study for your wine certification with spaced repetition, maps, '
            'tasting practice and a wine journal. Everything stays on this '
            'device and works offline.',
          ),
          SizedBox(height: 16),
          Text(
            'This app is about wine. It is meant for adults of legal '
            'drinking age where they live.',
          ),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              value: _ofAge,
              onChanged: (value) => setState(() => _ofAge = value ?? false),
              title: const Text('I am of legal drinking age where I live.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _ofAge ? _confirmAge : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
      _Step(
        icon: Icons.psychology_alt_outlined,
        title: 'How it works',
        body: const [
          _Point(
            icon: Icons.schedule,
            text:
                'Spaced repetition: each fact returns just before you would '
                'forget it, so your study time goes where it helps most.',
          ),
          _Point(
            icon: Icons.account_tree_outlined,
            text:
                'One fact, one memory: a flashcard, a multiple-choice '
                'question or a map all practise the same fact.',
          ),
          _Point(
            icon: Icons.fact_check_outlined,
            text:
                'Every fact cites its public source, such as the appellation '
                'rules. Facts stay marked unverified until a qualified '
                'reviewer checks them.',
          ),
          _Point(
            icon: Icons.inventory_2_outlined,
            text:
                'Log the wines you taste in the Cellar: what you study '
                'about them comes up sooner.',
          ),
        ],
        footer: FilledButton(
          onPressed: () => setState(() => _step = 2),
          child: const Text('Continue'),
        ),
      ),
      _Step(
        icon: Icons.school_outlined,
        title: 'Choose your track',
        body: const [
          Text(
            'Your dashboard and sessions follow the certification you pick. '
            'You can switch at any time without losing progress.',
          ),
          SizedBox(height: 16),
          TrackPicker(),
          SizedBox(height: 16),
          Text(
            'WSET and CMS are named only to describe study tracks. This app '
            'is not affiliated with or endorsed by the Wine & Spirit '
            'Education Trust or the Court of Master Sommeliers.',
          ),
        ],
        footer: FilledButton(
          onPressed: hasTrack ? _finish : null,
          child: const Text('Start studying'),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Semantics(
                    label: 'Step ${_step + 1} of ${steps.length}',
                    child: LinearProgressIndicator(
                      value: (_step + 1) / steps.length,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(child: steps[_step]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
  });

  final IconData icon;
  final String title;
  final List<Widget> body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The step's action stays in reach while its text scrolls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ...body,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: footer,
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    icon: Icons.quiz_outlined,
    title: 'Practice',
    description: 'Adaptive question sessions scheduled by spaced repetition.',
    plannedPhase: 'Phases 2 and 3',
  );
}

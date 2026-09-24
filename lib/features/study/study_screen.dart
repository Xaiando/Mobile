import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    icon: Icons.account_tree_outlined,
    title: 'Study',
    description: 'Browse the curriculum by region, grape and topic.',
    plannedPhase: 'Phase 3',
  );
}

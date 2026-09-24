import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class CellarScreen extends StatelessWidget {
  const CellarScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    icon: Icons.inventory_2_outlined,
    title: 'Cellar',
    description: 'Your wine journal, linked to what you study.',
    plannedPhase: 'Phase 5',
  );
}

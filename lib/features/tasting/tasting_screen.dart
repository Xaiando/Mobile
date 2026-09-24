import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class TastingScreen extends StatelessWidget {
  const TastingScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    icon: Icons.wine_bar_outlined,
    title: 'Tasting',
    description: 'Structured tasting practice in the format of your certification track.',
    plannedPhase: 'Phase 4',
  );
}

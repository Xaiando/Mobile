import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
    icon: Icons.home_outlined,
    title: 'Home',
    description:
        'Your study dashboard: reviews due, retention and curriculum coverage.',
    plannedPhase: 'Phases 3 and 6',
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/learner_state.dart';
import '../../core/database/app_database.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/settings/user_settings.dart';
import '../../core/study/study_providers.dart';

/// Settings (backlog R1): session sizes, appearance, units, and About.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final profile = ref.watch(learnerProfileProvider).value;
    final learner = ref.read(learnerSettingsProvider);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          heading('Study sessions'),
          if (profile == null)
            const ListTile(
              title: Text('Choose a track on Home to set your sessions.'),
            )
          else
            _SessionLimits(profile),
          heading('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppearanceMode>(
              segments: const [
                ButtonSegment(
                  value: AppearanceMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: AppearanceMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: AppearanceMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.appearance},
              onSelectionChanged: (selection) =>
                  learner.setAppearance(selection.single),
            ),
          ),
          heading('Units'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<TemperatureUnit>(
              segments: const [
                ButtonSegment(
                  value: TemperatureUnit.celsius,
                  label: Text('Celsius (°C)'),
                ),
                ButtonSegment(
                  value: TemperatureUnit.fahrenheit,
                  label: Text('Fahrenheit (°F)'),
                ),
              ],
              selected: {settings.temperatureUnit},
              onSelectionChanged: (selection) =>
                  learner.setTemperatureUnit(selection.single),
            ),
          ),
          heading('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About, sources and licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about'),
          ),
        ],
      ),
    );
  }
}

/// The session size and new-item budget (P-4), saved as they change.
class _SessionLimits extends ConsumerWidget {
  const _SessionLimits(this.profile);

  final UserProfile profile;

  static const _sizes = [5, 10, 15, 20, 25, 30, 40, 50];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.read(learnerProfilesProvider);
    final size = profile.sessionSize;
    final fresh = profile.newItemsPerSession;
    return Column(
      children: [
        ListTile(
          title: const Text('Items per session'),
          subtitle: const Text('Due reviews come first, then new items.'),
          trailing: DropdownButton<int>(
            value: _sizes.contains(size) ? size : null,
            hint: Text('$size'),
            items: [
              for (final value in _sizes)
                DropdownMenuItem(value: value, child: Text('$value')),
            ],
            onChanged: (value) => value == null
                ? null
                : profiles.setSessionLimits(
                    sessionSize: value,
                    newItems: fresh,
                  ),
          ),
        ),
        ListTile(
          title: const Text('New items per session'),
          subtitle: Text('At most $fresh new facts each session.'),
          trailing: DropdownButton<int>(
            value: fresh,
            items: [
              for (var value = 0; value <= size && value <= 20; value++)
                DropdownMenuItem(value: value, child: Text('$value')),
              if (fresh > 20)
                DropdownMenuItem(value: fresh, child: Text('$fresh')),
            ],
            onChanged: (value) => value == null
                ? null
                : profiles.setSessionLimits(sessionSize: size, newItems: value),
          ),
        ),
      ],
    );
  }
}

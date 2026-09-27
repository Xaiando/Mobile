import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../core/study/study_providers.dart';

/// Picks any installed selectable track. Switching keeps item memory (FS-12).
class TrackPicker extends ConsumerWidget {
  const TrackPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(selectableTracksProvider).value ?? const [];
    final active = ref.watch(learnerProfileProvider).value;
    if (tracks.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final track in tracks)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: ChoiceChip(
                key: ValueKey('track-${track.id}'),
                label: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 48
                        ? constraints.maxWidth - 48
                        : 0,
                  ),
                  child: Text(track.displayName, textAlign: TextAlign.center),
                ),
                showCheckmark: false,
                selected: active?.activeCertificationId == track.id,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(learnerProfilesProvider).selectTrack(track.id);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

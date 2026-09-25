import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../core/study/study_providers.dart';

/// Picks the certification track the queue studies for (spec §N): WSET
/// Level 3 or CMS Certified. Switching keeps every memory state (FS-12).
class TrackPicker extends ConsumerWidget {
  const TrackPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(selectableTracksProvider).value ?? const [];
    final active = ref.watch(learnerProfileProvider).value;
    if (tracks.isEmpty) return const SizedBox.shrink();
    return SegmentedButton<String>(
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      segments: [
        for (final track in tracks)
          ButtonSegment(
            value: track.id,
            label: Text(track.displayName, textAlign: TextAlign.center),
          ),
      ],
      selected: {?active?.activeCertificationId},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) return;
        ref.read(learnerProfilesProvider).selectTrack(selection.single);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/learner_state.dart';
import '../../core/curriculum/name_normalizer.dart';
import '../../core/database/database_providers.dart';
import '../../core/geography/map_practice_catalog.dart';
import '../../core/study/study_planner.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';
import '../home/track_picker.dart';
import 'study_session_controller.dart';

final mapPracticeScopesProvider = FutureProvider<List<MapPracticeScope>>((
  ref,
) async {
  final cards = await ref.watch(trackCardsProvider.future);
  if (cards == null) return const [];
  final clock = ref.watch(clockProvider);
  return MapPracticeCatalog(ref.watch(appDatabaseProvider))
      .scopes(cards, on: localToday(clock), now: utcNow(clock));
});

/// Choose a geographic scope from the active track before starting a session
/// containing only map formats. The ordinary due/new budgets still apply.
class MapPracticeScreen extends ConsumerStatefulWidget {
  const MapPracticeScreen({super.key});

  @override
  ConsumerState<MapPracticeScreen> createState() => _MapPracticeScreenState();
}

class _MapPracticeScreenState extends ConsumerState<MapPracticeScreen> {
  final _search = TextEditingController();
  String? _country;
  var _starting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _start(Set<String> itemIds) async {
    if (_starting) return;
    setState(() => _starting = true);
    await ref.read(studySessionProvider.notifier).startMaps(itemIds: itemIds);
    if (mounted) context.go('/practice');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learnerProfileProvider);
    final tracks = ref.watch(selectableTracksProvider).value ?? const [];
    final activeId = profile.value?.activeCertificationId;
    final activeName = [
      for (final track in tracks)
        if (track.id == activeId) track.displayName,
    ].firstOrNull;
    final scopes = ref.watch(mapPracticeScopesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Practice maps')),
      body: profile.value == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Choose a study track for map practice.'),
                    SizedBox(height: 16),
                    TrackPicker(),
                  ],
                ),
              ),
            )
          : switch (scopes) {
              AsyncData(value: final list) => _choices(
                list,
                activeName ?? 'Active track',
                ref.watch(trackCardsProvider).value ?? const [],
              ),
              AsyncError(:final error) => Center(
                child: Text('Map practice could not be loaded: $error'),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }

  Widget _choices(
    List<MapPracticeScope> scopes,
    String activeName,
    List<StudyCard> cards,
  ) {
    final countries = <String>{
      for (final scope in scopes) ?scope.countryName,
    }.toList()..sort();
    final selectedCountry = countries.contains(_country) ? _country : null;
    final term = normalizeName(_search.text);
    final filtered = [
      for (final scope in scopes)
        if ((selectedCountry == null || scope.countryName == selectedCountry) &&
            (term.isEmpty || normalizeName(scope.path).contains(term)))
          scope,
    ];
    final allIds = {for (final scope in scopes) ...scope.itemIds};
    final now = utcNow(ref.read(clockProvider));
    final readyIds = {
      for (final card in cards)
        if (allIds.contains(card.itemId) && (card.isNew || card.isDue(now)))
          card.itemId,
    };
    return ListView.builder(
      key: const ValueKey('map-region-results'),
      itemCount: filtered.length + 5,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ExpansionTile(
            title: Text('Study track · $activeName'),
            subtitle: const Text(
              'Switch track to change which maps are served',
            ),
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TrackPicker(),
              ),
            ],
          );
        }
        if (index == 1) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Choose a country, region or subregion. Each session uses your '
              'normal review schedule and asks map questions only.',
            ),
          );
        }
        if (index == 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey('map-country-${selectedCountry ?? 'all'}'),
              initialValue: selectedCountry ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('All countries')),
                for (final country in countries)
                  DropdownMenuItem(value: country, child: Text(country)),
              ],
              onChanged: (value) => setState(() {
                _country = value == '' ? null : value;
              }),
            ),
          );
        }
        if (index == 3) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('map-region-search'),
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search region or subregion',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          );
        }
        if (index == 4) {
          if (scopes.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No map questions are served on this track yet.'),
            );
          }
          return ListTile(
            key: const ValueKey('map-practice-all'),
            leading: const Icon(Icons.public),
            title: const Text('All mapped regions'),
            subtitle: Text(
              '${allIds.length} map facts · ${readyIds.length} ready',
            ),
            onTap: _starting || readyIds.isEmpty ? null : () => _start(allIds),
          );
        }
        final scope = filtered[index - 5];
        return ListTile(
          key: ValueKey('map-practice-${scope.id}'),
          leading: const Icon(Icons.map_outlined),
          title: Text(scope.name),
          subtitle: Text(
            '${scope.path}\n${scope.factCount} map facts · '
            '${scope.readyCount} ready',
          ),
          isThreeLine: true,
          onTap: _starting || scope.readyCount == 0
              ? null
              : () => _start(scope.itemIds),
        );
      },
    );
  }
}

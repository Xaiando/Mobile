import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diploma_tasting/diploma_tasting_flight.dart';
import '../../core/diploma_tasting/diploma_tasting_flight_providers.dart';

/// Untimed notes on three wines physically tasted by the learner.
/// Nothing here guesses an answer or certifies a WSET examination result.
class DiplomaTastingFlightScreen extends ConsumerStatefulWidget {
  const DiplomaTastingFlightScreen({super.key, required this.unitId});

  final String unitId;

  @override
  ConsumerState<DiplomaTastingFlightScreen> createState() =>
      _DiplomaTastingFlightScreenState();
}

class _DiplomaTastingFlightScreenState
    extends ConsumerState<DiplomaTastingFlightScreen> {
  DiplomaTastingFlightRepository? _repository;
  DiplomaTastingFlight? _flight;
  List<DiplomaTastingFlight> _history = const [];
  int _unreadable = 0;
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  bool _allowPop = false;
  bool _leaving = false;
  bool _writeFailed = false;
  bool _pointerError = false;
  String? _error;
  Future<void> _writeTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(
        diplomaTastingFlightRepositoryProvider.future,
      );
      if (!mounted) return;
      setState(() => _repository = repository);
      final history = await repository.historyWithDiagnostics(widget.unitId);
      DiplomaTastingFlight? current;
      try {
        current = await repository.current(widget.unitId);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _history = history.entries;
          _unreadable = history.unreadableCount;
          _loading = false;
          _pointerError = true;
          _error = '$error';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _history = history.entries;
        _unreadable = history.unreadableCount;
        _flight = current;
        _loading = false;
        _pointerError = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _queue(Future<DiplomaTastingFlight> Function() write) {
    _writeTail = _writeTail
        .then((_) async {
          final changed = await write();
          if (mounted) {
            setState(() {
              _flight = changed;
              if (!_writeFailed) _error = null;
            });
          }
        })
        .catchError((Object _) {
          _writeFailed = true;
          if (mounted) {
            setState(
              () => _error =
                  'Your latest change could not be saved. Check this flight '
                  'before recording it.',
            );
          }
        });
  }

  void _draftText(String key, String text) {
    // A callback already dispatched by an editable field can arrive before
    // the disabled state has rebuilt. Do not extend the autosave tail after a
    // transition has captured it.
    if (_busy || _leaving) return;
    final id = _flight!.id;
    if (key == 'comparison') {
      _queue(() => _repository!.saveReflection(id, text));
    } else if (key == 'self_review') {
      _queue(() => _repository!.saveSelfReview(id, text));
    } else {
      final parts = key.split(':');
      _queue(
        () => _repository!.saveEvidence(
          id,
          int.parse(parts.first),
          parts.last,
          text,
        ),
      );
    }
  }

  Future<void> _leave(Object? result) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    var popRequested = false;
    try {
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error =
              'A change could not be saved. Keep this screen open and '
              'check your draft before leaving.',
        );
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.of(context).pop(result);
        popRequested = true;
      }
    } finally {
      if (!popRequested) {
        if (mounted) {
          setState(() => _leaving = false);
        } else {
          _leaving = false;
        }
      }
    }
  }

  Future<void> _reloadSavedDraft() async {
    await _writeTail;
    if (!mounted) return;
    setState(() {
      _flight = null;
      _loading = true;
      _writeFailed = false;
      _error = null;
    });
    await _load();
  }

  Future<void> _action(
    Future<DiplomaTastingFlight?> Function(DiplomaTastingFlightRepository)
    task, {
    bool resetStep = true,
  }) async {
    if (_busy || _repository == null) return;
    setState(() {
      _busy = true;
      if (!_writeFailed) _error = null;
    });
    try {
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error = 'A change could not be saved. Check your draft.',
        );
        return;
      }
      final result = await task(_repository!);
      final history = await _repository!.historyWithDiagnostics(widget.unitId);
      if (!mounted) return;
      setState(() {
        _flight = result;
        _history = history.entries;
        _unreadable = history.unreadableCount;
        if (resetStep) _step = 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goToStep(int step) async {
    await _writeTail;
    if (mounted) setState(() => _step = step);
  }

  void _choose(
    int index,
    DiplomaObservationAttribute attribute,
    String value,
    bool selected,
  ) {
    final id = _flight!.id;
    _queue(() async {
      final current = await _repository!.read(id);
      final previous = current.wines[index].observations[attribute.key] ?? {};
      final choices = attribute.isSingle
          ? <String>{if (selected) value}
          : (<String>{...previous}
              ..removeWhere((choice) => choice == value && !selected)
              ..addAll(selected ? {value} : const <String>{}));
      return _repository!.choose(id, index, attribute.key, choices);
    });
  }

  Widget _wineStep(DiplomaTastingFlight flight, int index) {
    final wine = flight.wines[index];
    final sections = {
      for (final attribute in wine.attributes) attribute.section,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wine ${index + 1} of 3',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: ValueKey('diploma-flight-physical-$index'),
          value: wine.physicallyTasted,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'I physically tasted this ${flight.unitId == 'D4' ? 'sparkling' : 'fortified'} wine',
          ),
          subtitle: const Text(
            'A described example or imagined wine does not count.',
          ),
          onChanged: _busy
              ? null
              : (value) {
                  _queue(
                    () => _repository!.acknowledgePhysical(
                      flight.id,
                      index,
                      value ?? false,
                    ),
                  );
                },
        ),
        for (final section in sections)
          ExpansionTile(
            key: ValueKey('${flight.id}-$index-$section'),
            title: Text(section),
            children: [
              for (final attribute in wine.attributes.where(
                (attribute) => attribute.section == section,
              ))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${attribute.label}${attribute.isRequired ? ' *' : ''}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final option in attribute.values)
                            FilterChip(
                              key: ValueKey(
                                'diploma-flight-observation-$index-${attribute.key}-${option.key}',
                              ),
                              label: Text(option.label),
                              selected:
                                  wine.observations[attribute.key]?.contains(
                                    option.key,
                                  ) ??
                                  false,
                              onSelected: _busy
                                  ? null
                                  : (selected) => _choose(
                                      index,
                                      attribute,
                                      option.key,
                                      selected,
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Text('Your evidence', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Describe the wine in your glass. There is no hidden answer key.',
        ),
        for (final prompt in wine.prompts)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              key: ValueKey('diploma-flight-evidence-$index-${prompt.id}'),
              enabled: !_busy && !_leaving,
              initialValue: wine.evidence[prompt.id] ?? '',
              minLines: 2,
              maxLines: 5,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: prompt.id.replaceAll('_', ' '),
                helperText: prompt.prompt,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) => _draftText('$index:${prompt.id}', text),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Missing: ${[if (!wine.physicallyTasted) 'physical tasting', ...wine.missingObservations.map((a) => a.label), ...wine.missingEvidence.map((p) => p.id.replaceAll('_', ' '))].join(', ')}',
        ),
      ],
    );
  }

  Widget _comparisonStep(DiplomaTastingFlight flight) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Compare and review', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text('Complete physical wines: ${flight.completeWineCount} of 3'),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('diploma-flight-comparison'),
        enabled: !_busy && !_leaving,
        initialValue: flight.reflection,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        decoration: InputDecoration(
          labelText: 'Three-wine comparison',
          helperText: flight.comparisonPrompt,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) => _draftText('comparison', text),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('diploma-flight-self-review'),
        enabled: !_busy && !_leaving,
        initialValue: flight.selfReview,
        minLines: 3,
        maxLines: 6,
        maxLength: 4000,
        decoration: InputDecoration(
          labelText: 'Your self-review',
          helperText: flight.selfReviewPrompt,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) => _draftText('self_review', text),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('diploma-flight-mark-reviewed'),
        onPressed: _busy
            ? null
            : () => _action(
                (repository) => repository.markSelfReviewed(flight.id),
                resetStep: false,
              ),
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(
          flight.selfReviewedAt == null
              ? 'Mark evidence reviewed'
              : 'Evidence reviewed',
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Recording a flight means you documented three real wines and '
        'reviewed your reasoning. It is not a tasting score or exam result.',
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('diploma-flight-finish'),
        onPressed: _busy
            ? null
            : () => _action((repository) => repository.finish(flight.id)),
        child: const Text('Record physical practice'),
      ),
    ],
  );

  Widget _historySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Saved flights', style: Theme.of(context).textTheme.titleMedium),
      if (_unreadable > 0)
        Text(
          '$_unreadable saved flight${_unreadable == 1 ? '' : 's'} could not be read.',
          key: const ValueKey('diploma-flight-history-warning'),
        ),
      if (_history.isEmpty) const Text('No flights recorded yet.'),
      for (final flight in _history.take(10))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            flight.isSubmitted
                ? 'Three-wine physical practice recorded'
                : flight.finishReason == 'abandoned'
                ? 'Abandoned flight'
                : 'Saved draft',
          ),
          subtitle: Text(
            '${flight.startedAt.toLocal().toString().split('.').first} · '
            '${flight.completeWineCount} of 3 wines',
          ),
          trailing: !flight.isFinished && _flight == null
              ? TextButton(
                  onPressed: _busy
                      ? null
                      : () => _action(
                          (repository) => repository.resume(flight.id),
                        ),
                  child: const Text('Resume'),
                )
              : null,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final unit = widget.unitId == 'D4' ? 'Sparkling' : 'Fortified';
    final wineKind = unit.toLowerCase();
    final flight = _flight;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(result);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.unitId} $unit tasting practice')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Taste three actual $wineKind wines and record what you observe. '
                    'This untimed exercise supports the Diploma tasting outcome; '
                    'your notes and self-review are private practice evidence.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_writeFailed)
                      TextButton(
                        onPressed: _reloadSavedDraft,
                        child: const Text(
                          'Reload saved draft (discard unsaved edits)',
                        ),
                      ),
                    if (_pointerError && _repository != null && flight == null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await _repository!.resetCurrentPointer(
                                  widget.unitId,
                                );
                                await _load();
                              },
                        child: const Text('Repair saved draft pointer'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  if (flight == null || flight.isFinished) ...[
                    if (flight?.isSubmitted ?? false)
                      const Text(
                        'Physical practice recorded. This does not certify '
                        'tasting accuracy or an exam pass.',
                      ),
                    FilledButton(
                      key: const ValueKey('diploma-flight-start'),
                      onPressed: _busy || _repository == null || _pointerError
                          ? null
                          : () => _action(
                              (repository) => repository.start(widget.unitId),
                            ),
                      child: Text('Start three-wine $wineKind flight'),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < 4; i++)
                          ChoiceChip(
                            key: ValueKey('diploma-flight-step-$i'),
                            label: Text(i == 3 ? 'Compare' : 'Wine ${i + 1}'),
                            selected: _step == i,
                            onSelected: (_) => _goToStep(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_step < 3)
                      _wineStep(flight, _step)
                    else
                      _comparisonStep(flight),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _action(
                              (repository) => repository.abandon(flight.id),
                            ),
                      child: const Text('Abandon this flight'),
                    ),
                  ],
                  const Divider(height: 32),
                  _historySection(),
                ],
              ),
      ),
    );
  }
}

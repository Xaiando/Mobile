import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tasting/tasting_practice.dart';
import '../../core/tasting_guidance/guided_tasting.dart';
import '../../core/tasting_guidance/guided_tasting_providers.dart';
import '../../core/study/study_providers.dart';

class GuidedTastingScreen extends ConsumerStatefulWidget {
  const GuidedTastingScreen({super.key, this.initialLevel});
  final int? initialLevel;
  @override
  ConsumerState<GuidedTastingScreen> createState() =>
      _GuidedTastingScreenState();
}

class _GuidedTastingScreenState extends ConsumerState<GuidedTastingScreen> {
  GuidedTastingRepository? _repository;
  GuidedTastingRecord? _record;
  GridLayout? _grid;
  Map<String, Set<String>> _observations = {};
  List<GuidedTastingRecord> _history = [];
  int _unreadableHistory = 0;
  final _evidence = <String, TextEditingController>{};
  Future<void> _writeTail = Future.value();
  int _level = 1;
  String _mode = 'physical';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _evidence.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRecord(
    GuidedTastingRecord? record,
    GridLayout? grid,
    Map<String, Set<String>> observations,
  ) {
    for (final c in _evidence.values) {
      c.dispose();
    }
    _evidence.clear();
    _record = record;
    _grid = grid;
    _observations = observations;
    if (record != null) {
      _level = record.level.level;
      for (final p in record.level.evidencePrompts) {
        _evidence[p.id] = TextEditingController(
          text: record.evidence[p.id] ?? '',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(guidedTastingRepositoryProvider.future);
      _repository = repository;
      final record = await repository.current();
      final profile = await ref.read(learnerProfilesProvider).current();
      if (record == null) {
        final certification = profile?.activeCertificationId ?? '';
        _level =
            widget.initialLevel ??
            (RegExp(r'^WSET_L[1-3]$').hasMatch(certification)
                ? int.parse(certification.substring(6))
                : 1);
      }
      final grid = record == null ? null : await repository.layout(record);
      final observations = record == null
          ? <String, Set<String>>{}
          : await repository.observations(record);
      final history = await repository.historyWithDiagnostics();
      if (mounted) {
        setState(() {
          _setRecord(record, grid, observations);
          _history = history.entries;
          _unreadableHistory = history.unreadableCount;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _action(Future<GuidedTastingRecord?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _writeTail;
      final record = await action();
      final grid = record == null ? null : await _repository!.layout(record);
      final observations = record == null
          ? <String, Set<String>>{}
          : await _repository!.observations(record);
      final history = await _repository!.historyWithDiagnostics();
      if (mounted) {
        setState(() {
          _setRecord(record, grid, observations);
          _history = history.entries;
          _unreadableHistory = history.unreadableCount;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveEvidence(String promptId, String text) {
    final id = _record!.sessionId;
    _writeTail = _writeTail.then((_) async {
      try {
        final record = await _repository!.evidence(id, promptId, text);
        if (mounted && _record?.sessionId == id) _record = record;
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
    });
  }

  Future<void> _start() => _action(() async {
    await ref.read(learnerProfilesProvider).selectTrack('WSET_L$_level');
    return _repository!.start(
      _level,
      caseId: _mode == 'physical' ? null : _mode.substring(5),
    );
  });

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return Scaffold(
      appBar: AppBar(title: const Text('Guided tasting')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Describe the wine and explain your evidence. Physical wines receive no automatic correctness score. Original training cases provide a reference to discuss after you finish.',
                ),
                const SizedBox(height: 12),
                if (_unreadableHistory > 0)
                  Text(
                    '$_unreadableHistory saved guided ${_unreadableHistory == 1 ? 'record could' : 'records could'} not be read. Readable history remains available; unreadable data is preserved in backups.',
                    key: const ValueKey('guided-history-warning'),
                  ),
                if (_error != null) ...[
                  Text(_error!, key: const ValueKey('guided-tasting-error')),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                      if (_repository != null)
                        TextButton(
                          onPressed: () => _action(() async {
                            await _repository!.leaveCurrent();
                            return null;
                          }),
                          child: const Text('Reset saved selection'),
                        ),
                    ],
                  ),
                ],
                if (record == null)
                  ..._setup()
                else ...[
                  Text(
                    'Level ${record.level.level} · ${record.calibration?.title ?? 'Physical wine observation'}',
                  ),
                  const Text(
                    'Untimed guided practice. This is not the paired tasting examination format.',
                  ),
                  if (record.calibration != null)
                    Text(record.calibration!.description),
                  for (final section in _grid!.sections) ...[
                    const SizedBox(height: 24),
                    Text(
                      section,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final attribute in _grid!.inSection(section)) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${attribute.attribute.label}${attribute.attribute.isRequired ? ' · required' : ''}',
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final value in attribute.values)
                              FilterChip(
                                key: ValueKey(
                                  'guided-observation-${attribute.key}-${value.valueKey}',
                                ),
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth > 48
                                        ? constraints.maxWidth - 48
                                        : 0,
                                  ),
                                  child: Text(value.label),
                                ),
                                selected:
                                    _observations[attribute.key]?.contains(
                                      value.valueKey,
                                    ) ??
                                    false,
                                onSelected: record.isFinished || _busy
                                    ? null
                                    : (selected) {
                                        final values = attribute.isSingle
                                            ? <String>{}
                                            : {
                                                ...?_observations[attribute
                                                    .key],
                                              };
                                        if (selected) {
                                          values.add(value.valueKey);
                                        } else {
                                          values.remove(value.valueKey);
                                        }
                                        _action(
                                          () => _repository!.choose(
                                            record.sessionId,
                                            attribute.key,
                                            values,
                                          ),
                                        );
                                      },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Explain your evidence',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final prompt in record.level.evidencePrompts) ...[
                    const SizedBox(height: 12),
                    Text(prompt.prompt),
                    const SizedBox(height: 8),
                    TextField(
                      key: ValueKey('guided-evidence-${prompt.id}'),
                      controller: _evidence[prompt.id],
                      minLines: 3,
                      maxLines: 10,
                      maxLength: 20000,
                      readOnly: record.isFinished || _busy,
                      decoration: const InputDecoration(
                        labelText: 'Your evidence',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) => _saveEvidence(prompt.id, text),
                    ),
                  ],
                  if (record.isFinished) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Observation and evidence saved. No official tasting grade or qualification is inferred.',
                      key: ValueKey('guided-tasting-complete'),
                    ),
                    if (record.calibration case final calibration?) ...[
                      const SizedBox(height: 12),
                      const Text('Training reference observations'),
                      for (final reference
                          in calibration.referenceObservations) ...[
                        Text(_referenceLabels(reference)),
                        Text(reference.explanation),
                      ],
                      Text(
                        calibration.feedback,
                        key: const ValueKey('guided-tasting-feedback'),
                      ),
                      const Text(
                        'Your self-assessment: select criteria your explanation supports.',
                      ),
                      for (final criterion in calibration.criteria)
                        CheckboxListTile(
                          title: Text(criterion.text),
                          value: record.selfAssessment.contains(criterion.id),
                          onChanged: _busy
                              ? null
                              : (selected) {
                                  final checked = {...record.selfAssessment};
                                  if (selected == true) {
                                    checked.add(criterion.id);
                                  } else {
                                    checked.remove(criterion.id);
                                  }
                                  _action(
                                    () => _repository!.selfAssess(
                                      record.sessionId,
                                      checked,
                                    ),
                                  );
                                },
                        ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  if (!record.isFinished)
                    FilledButton(
                      key: const ValueKey('guided-tasting-finish'),
                      onPressed: _busy
                          ? null
                          : () => _action(
                              () => _repository!.finish(record.sessionId),
                            ),
                      child: const Text('Finish observation and evidence'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                            await _repository!.leaveCurrent();
                            return null;
                          }),
                    child: const Text('Leave this guided session'),
                  ),
                ],
                if (record == null && _history.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Saved guided sessions'),
                  for (final saved in _history)
                    ListTile(
                      key: ValueKey('guided-history-${saved.sessionId}'),
                      title: Text(
                        'Level ${saved.level.level} · ${saved.calibration?.title ?? 'Physical wine'}',
                      ),
                      subtitle: Text(
                        saved.isFinished
                            ? 'Observation and evidence saved'
                            : 'Saved draft',
                      ),
                      onTap: () =>
                          _action(() => _repository!.resume(saved.sessionId)),
                    ),
                ],
              ],
            ),
    );
  }

  String _referenceLabels(TastingReferenceObservation reference) {
    final attribute = _grid!.attributes.singleWhere(
      (a) => a.key == reference.attributeKey,
    );
    return '${attribute.attribute.label}: ${attribute.values.where((v) => reference.valueKeys.contains(v.valueKey)).map((v) => v.label).join(', ')}';
  }

  List<Widget> _setup() => [
    DropdownButtonFormField<int>(
      initialValue: _level,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Study level'),
      items: [
        for (var level = 1; level <= 3; level++)
          DropdownMenuItem(value: level, child: Text('WSET Level $level')),
      ],
      onChanged: _busy
          ? null
          : (level) => setState(() {
              _level = level ?? 1;
              _mode = 'physical';
            }),
    ),
    const SizedBox(height: 12),
    RadioGroup<String>(
      groupValue: _mode,
      onChanged: (value) {
        if (!_busy && value != null) setState(() => _mode = value);
      },
      child: Column(
        children: [
          RadioListTile<String>(
            value: 'physical',
            title: const Text('Observe a physical wine'),
            enabled: !_busy,
          ),
          for (final calibration
              in _repository?.bank.cases ?? <TastingCalibrationCase>[])
            if (calibration.level == _level)
              RadioListTile<String>(
                value: 'case:${calibration.id}',
                title: Text(calibration.title),
                subtitle: const Text('Original training case'),
                enabled: !_busy,
              ),
        ],
      ),
    ),
    FilledButton(
      key: const ValueKey('guided-tasting-start'),
      onPressed: _busy || _repository == null ? null : _start,
      child: const Text('Start guided tasting'),
    ),
  ];
}

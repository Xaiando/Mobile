import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sommelier/core/diploma_tasting/d3_tasting_paper.dart';
import 'package:sommelier/core/diploma_tasting/d3_tasting_paper_providers.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/core/time/utc_clock.dart';

/// Original sustained practice on actual wines; never a mark or unit pass.
class D3TastingPaperScreen extends ConsumerStatefulWidget {
  const D3TastingPaperScreen({super.key});

  @override
  ConsumerState<D3TastingPaperScreen> createState() =>
      _D3TastingPaperScreenState();
}

/// This count is separate from three-wine flights, knowledge and exam results.
class D3TimedPracticeAffordance extends ConsumerWidget {
  const D3TimedPracticeAffordance({super.key, this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidence = ref.watch(d3TastingPaperEvidenceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (evidence) {
          AsyncData(:final value) => Text(
            'Reviewed timed D3 papers: ${value.reviewedGrouped} grouped · '
            '${value.reviewedMixed} mixed. Self-reviewed participation, '
            'not a tasting grade or unit pass.'
            '${value.unreadableCount > 0 ? " Some saved paper records could not be read." : ""}',
            key: const ValueKey('wset_unit_timed_papers_D3'),
          ),
          AsyncError() => const Text(
            'Saved timed-paper participation could not be read. Other progress is unchanged.',
            key: ValueKey('wset_unit_timed_papers_D3'),
          ),
          _ => const Text(
            'Reading saved timed-paper participation…',
            key: ValueKey('wset_unit_timed_papers_D3'),
          ),
        },
        TextButton(
          key: const ValueKey('wset_unit_timed_papers_open_D3'),
          onPressed: onOpen,
          child: const Text('Timed six-wine D3 practice'),
        ),
      ],
    );
  }
}

class _D3TastingPaperScreenState extends ConsumerState<D3TastingPaperScreen> {
  D3TastingPaperRepository? _repository;
  D3TastingPaper? _paper;
  List<D3TastingPaper> _history = const [];
  final _editors = <String, TextEditingController>{};
  final _retiredEditors = <TextEditingController>{};
  final _drafts = <(String, String), String>{};
  Future<void> _writeTail = Future<void>.value();
  Completer<void>? _transitionDone;
  Timer? _timer;
  int _step = 0;
  int _unreadable = 0;
  bool _loading = true;
  bool _busy = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _writeFailed = false;
  bool _pointerError = false;
  bool _expiryQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await _load();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _editors.values) {
      controller.dispose();
    }
    for (final controller in _retiredEditors) {
      controller.dispose();
    }
    _retiredEditors.clear();
    super.dispose();
  }

  DateTime get _now => utcNow(ref.read(clockProvider));
  bool get _editable =>
      _paper != null &&
      !_paper!.isFinished &&
      _now.isBefore(_paper!.deadline) &&
      !_busy &&
      !_leaving &&
      !_writeFailed;

  void _hydrate(D3TastingPaper? paper) {
    final samePaper = paper != null && _paper?.id == paper.id;
    if (!samePaper) {
      final retired = _editors.values.toList();
      _retiredEditors.addAll(retired);
      _editors.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in retired) {
          if (_retiredEditors.remove(controller)) controller.dispose();
        }
      });
    }
    _drafts.clear();
    void seed(String key, String text) {
      final controller = _editors.putIfAbsent(key, TextEditingController.new);
      controller.value = TextEditingValue(text: text);
    }

    if (paper != null) {
      for (var index = 0; index < paper.wines.length; index++) {
        for (final prompt in paper.wines[index].prompts) {
          seed(
            'wine:$index:${prompt.id}',
            paper.wines[index].evidence[prompt.id] ?? '',
          );
        }
      }
      for (var index = 0; index < paper.groupComparisons.length; index++) {
        seed('comparison:$index', paper.groupComparisons[index]);
      }
      seed('review', paper.selfReview);
    }
    _paper = paper;
  }

  void _accept(D3TastingPaper changed, {bool hydrate = false}) {
    if (!mounted) return;
    setState(() {
      if (hydrate ||
          _paper?.id != changed.id ||
          (!_paper!.isFinished && changed.isFinished)) {
        _hydrate(changed);
      } else {
        _paper = changed;
      }
      if (!_writeFailed) _error = null;
    });
  }

  Future<void> _refreshHistory() async {
    final history = await _repository!.historyWithDiagnostics();
    if (!mounted) return;
    setState(() {
      _history = history.entries;
      _unreadable = history.unreadableCount;
    });
  }

  Future<bool> _load() async {
    try {
      final repository = await ref.read(
        d3TastingPaperRepositoryProvider.future,
      );
      if (!mounted) return false;
      _repository = repository;
      await _refreshHistory();
      D3TastingPaper? paper;
      try {
        paper = await repository.current();
      } catch (_) {
        if (!mounted) return false;
        setState(() {
          _pointerError = true;
          _loading = false;
          _error = 'The current paper pointer could not be read. Saved history is preserved.';
        });
        return false;
      }
      // current() may have committed expiry and removed the active pointer.
      // Refresh after it, preserving the earlier history for pointer failure.
      await _refreshHistory();
      if (!mounted) return false;
      setState(() {
        _hydrate(paper);
        _loading = false;
        _pointerError = false;
        _error = null;
      });
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Saved practice could not be loaded. Nothing was overwritten.';
        });
      }
      return false;
    }
  }

  void _tick() {
    if (!mounted || _paper == null || _paper!.isFinished || _busy || _leaving) {
      return;
    }
    if (!_now.isBefore(_paper!.deadline)) {
      if (!_expiryQueued) unawaited(_expire());
    } else {
      setState(() {});
    }
  }

  Future<void> _expire() async {
    if (_expiryQueued || _paper == null) return;
    _expiryQueued = true;
    final done = Completer<void>();
    _transitionDone = done;
    final id = _paper!.id;
    if (mounted) setState(() => _busy = true);
    try {
      await _writeTail;
      final durable = await _repository!.read(id);
      if (_paper?.id == id) _accept(durable, hydrate: true);
      await _refreshHistory();
    } catch (_) {
      if (mounted) {
        setState(() {
          _writeFailed = true;
          _error = 'The saved end state could not be read. Reload saved practice before leaving.';
        });
      }
    } finally {
      _expiryQueued = false;
      done.complete();
      if (identical(_transitionDone, done)) _transitionDone = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String id, Future<D3TastingPaper> Function() task) async {
    if (_writeFailed || _paper?.id != id || _paper!.isFinished) return;
    try {
      final changed = await task();
      if (_paper?.id == id) _accept(changed);
    } catch (_) {
      // A late mutation may commit expiry before rejecting its payload.
      // Hydrate the durable ended record; never display a rejected late draft.
      try {
        final durable = await _repository!.read(id);
        if (durable.isFinished) {
          if (_paper?.id == id) _accept(durable, hydrate: true);
          return;
        }
      } catch (_) {
        // An unreadable record is preserved for explicit recovery.
      }
      if (mounted) {
        setState(() {
          _writeFailed = true;
          _error = 'Your latest change could not be saved. Reload saved practice before leaving.';
        });
      }
    }
  }

  void _draft(String key, String text) {
    if (!_editable) return;
    final id = _paper!.id;
    final pendingKey = (id, key);
    _drafts[pendingKey] = text;
    _writeTail = _writeTail.then((_) async {
      final latest = _drafts.remove(pendingKey);
      if (latest == null) return;
      await _save(id, () {
        final parts = key.split(':');
        if (parts.first == 'comparison') {
          return _repository!.comparison(id, int.parse(parts[1]), latest);
        }
        return _repository!.answer(id, int.parse(parts[1]), parts[2], latest);
      });
    });
  }

  void _queue(Future<D3TastingPaper> Function(String id) task) {
    if (!_editable) return;
    final id = _paper!.id;
    _writeTail = _writeTail.then((_) => _save(id, () => task(id)));
  }

  void _choose(
    int index,
    DiplomaObservationAttribute attribute,
    String value,
    bool selected,
  ) {
    _queue((id) async {
      final durable = await _repository!.read(id);
      final previous = durable.wines[index].observations[attribute.key] ?? {};
      final choices = attribute.isSingle
          ? <String>{if (selected) value}
          : (<String>{...previous}
              ..removeWhere((choice) => choice == value && !selected)
              ..addAll(selected ? {value} : const <String>{}));
      return _repository!.observation(id, index, attribute.key, choices);
    });
  }

  Future<void> _transition(Future<void> Function() task) async {
    if (_busy || _leaving) return;
    final done = Completer<void>();
    _transitionDone = done;
    setState(() => _busy = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error =
              'Reload the saved draft before navigating or ending practice.',
        );
        return;
      }
      await task();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'This action could not be completed. Saved records are preserved.',
        );
      }
    } finally {
      done.complete();
      if (identical(_transitionDone, done)) _transitionDone = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(Object? result) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    FocusManager.instance.primaryFocus?.unfocus();
    var popped = false;
    try {
      await _transitionDone?.future;
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error =
              'Reload saved practice before leaving. A change failed to save.',
        );
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.of(context).pop(result);
        popped = true;
      }
    } finally {
      if (!popped && mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _reload() async {
    if (_busy || _leaving) return;
    final done = Completer<void>();
    _transitionDone = done;
    setState(() => _busy = true);
    FocusManager.instance.primaryFocus?.unfocus();
    await _writeTail;
    final id = _paper?.id;
    try {
      var loaded = false;
      if (id == null) {
        loaded = await _load();
      } else {
        final durable = await _repository!.read(id);
        _accept(durable, hydrate: true);
        await _refreshHistory();
        loaded = true;
      }
      if (mounted && loaded) {
        setState(() {
          _writeFailed = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Saved practice is still unreadable. Its data has been preserved.',
        );
      }
    } finally {
      done.complete();
      if (identical(_transitionDone, done)) _transitionDone = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(D3TastingPaperKind kind) => _transition(() async {
    final paper = await _repository!.start(kind);
    _accept(paper, hydrate: true);
    if (mounted) setState(() => _step = 0);
    await _refreshHistory();
  });

  Future<void> _open(D3TastingPaper paper) => _transition(() async {
    final durable = paper.isFinished
        ? await _repository!.read(paper.id)
        : await _repository!.resume(paper.id);
    _accept(durable, hydrate: true);
    if (mounted) setState(() => _step = 0);
  });

  Future<void> _go(int step) => _transition(() async {
    if (_paper != null && !_paper!.isFinished) {
      final durable = await _repository!.read(_paper!.id);
      _accept(durable);
    }
    if (mounted) setState(() => _step = step);
  });

  Future<void> _end(bool abandon) => _transition(() async {
    final id = _paper!.id;
    final ended = abandon
        ? await _repository!.abandon(id)
        : await _repository!.finish(id);
    _accept(ended, hydrate: true);
    if (mounted) setState(() => _step = 6);
    await _refreshHistory();
  });

  Future<void> _review() => _transition(() async {
    final changed = await _repository!.review(
      _paper!.id,
      _editors['review']!.text,
    );
    _accept(changed, hydrate: true);
    await _refreshHistory();
  });

  Future<void> _menu() => _transition(() async {
    await _refreshHistory();
    if (mounted) {
      setState(() {
        _hydrate(null);
        _step = 0;
      });
    }
  });

  Future<void> _copyRecord() => _transition(() async {
    final durable = await _repository!.read(_paper!.id);
    _accept(durable);
    final text =
        StringBuffer('D3 timed six-wine practice · ${durable.kind.name}\n')
          ..writeln(
            'Private practice; no independently assessed grade or pass.',
          )
          ..writeln('Started: ${durable.startedAt.toIso8601String()}')
          ..writeln('Deadline: ${durable.deadline.toIso8601String()}')
          ..writeln('End: ${durable.finishReason ?? "active"}');
    for (var index = 0; index < durable.wines.length; index++) {
      final wine = durable.wines[index];
      text
        ..writeln('\nWine ${index + 1}')
        ..writeln('Physically tasted: ${wine.physicallyTasted}');
      for (final attribute in wine.attributes) {
        text.writeln(
          '${attribute.label}: ${[for (final value in attribute.values)
            if (wine.observations[attribute.key]?.contains(value.key) ?? false) value.label].join(", ")}',
        );
      }
      for (final prompt in wine.prompts) {
        text
          ..writeln(prompt.prompt)
          ..writeln(wine.evidence[prompt.id] ?? '');
      }
    }
    for (var index = 0; index < durable.groupComparisons.length; index++) {
      text
        ..writeln('\n${durable.comparisonPrompts[index]}')
        ..writeln(durable.groupComparisons[index]);
    }
    text
      ..writeln('\nPost-paper self-review')
      ..writeln(durable.selfReview);
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved practice copied.')));
    }
  });

  Widget _historyList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Saved timed papers'),
      if (_unreadable > 0)
        Text(
          '$_unreadable saved paper records could not be read. Other history is preserved.',
        ),
      if (_history.isEmpty) const Text('No timed papers saved yet.'),
      for (final paper in _history)
        ListTile(
          title: Text(
            '${paper.kind.name} · ${paper.completeWineCount} of 6 complete',
          ),
          subtitle: Text(
            '${paper.startedAt.toLocal()} · '
            '${paper.isReviewed ? "self-reviewed participation" : paper.finishReason ?? "active"}',
          ),
          trailing: TextButton(
            key: ValueKey('d3-paper-history-${paper.id}'),
            onPressed: _busy ? null : () => _open(paper),
            child: Text(paper.isFinished ? 'View' : 'Resume'),
          ),
        ),
    ],
  );

  Widget _setup() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Taste six actual still wines under one 90-minute deadline. '
        'Ask someone else to hide their identities and number them Wine 1–6. '
        'Choose the app-authored arrangement of two groups of three or a mixed '
        'set of six. Start another 90-minute paper later for sustained practice; '
        'these arrangements do not specify official paper layouts.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Original observations and comparison prompts; no official questions, tasting answer key, score or qualification claim.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            key: const ValueKey('d3-paper-start-grouped'),
            onPressed: _busy || _repository == null || _pointerError
                ? null
                : () => _start(D3TastingPaperKind.grouped),
            child: const Text('Start two groups of three'),
          ),
          FilledButton(
            key: const ValueKey('d3-paper-start-mixed'),
            onPressed: _busy || _repository == null || _pointerError
                ? null
                : () => _start(D3TastingPaperKind.mixed),
            child: const Text('Start mixed six-wine paper'),
          ),
        ],
      ),
      if (_pointerError)
        TextButton(
          key: const ValueKey('d3-paper-reset-pointer'),
          onPressed: _busy
              ? null
              : () => _transition(() async {
                  await _repository!.resetCurrentPointer();
                  if (mounted) setState(() => _pointerError = false);
                  await _load();
                }),
          child: const Text('Reset current pointer; preserve saved papers'),
        ),
      const SizedBox(height: 24),
      _historyList(),
    ],
  );

  Widget _wine(D3TastingPaper paper, int index) {
    final wine = paper.wines[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wine ${index + 1}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (paper.kind == D3TastingPaperKind.grouped)
          Text(index < 3 ? 'Group 1 · Wines 1–3' : 'Group 2 · Wines 4–6'),
        CheckboxListTile(
          key: ValueKey('d3-paper-tasted-$index'),
          contentPadding: EdgeInsets.zero,
          value: wine.physicallyTasted,
          onChanged: _editable
              ? (value) => _queue(
                  (id) => _repository!.markTasted(id, index, value ?? false),
                )
              : null,
          title: const Text('I physically tasted this still wine'),
          subtitle: const Text(
            'An imagined wine or supplied example does not count.',
          ),
        ),
        for (final section in {for (final a in wine.attributes) a.section}) ...[
          Text(section, style: Theme.of(context).textTheme.titleMedium),
          for (final attribute in wine.attributes.where(
            (a) => a.section == section,
          )) ...[
            Text('${attribute.label}${attribute.isRequired ? " *" : ""}'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in attribute.values)
                  FilterChip(
                    key: ValueKey(
                      'd3-paper-observation-$index-${attribute.key}-${value.key}',
                    ),
                    label: Text(value.label),
                    selected:
                        wine.observations[attribute.key]?.contains(value.key) ??
                        false,
                    onSelected: _editable
                        ? (selected) =>
                              _choose(index, attribute, value.key, selected)
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
        for (final prompt in wine.prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              key: ValueKey('d3-paper-evidence-$index-${prompt.id}'),
              controller: _editors['wine:$index:${prompt.id}'],
              enabled: _editable,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: prompt.id.replaceAll('_', ' '),
                helperText: prompt.prompt,
                helperMaxLines: 5,
              ),
              onChanged: (text) => _draft('wine:$index:${prompt.id}', text),
            ),
          ),
        Text(
          'Complete wines: ${paper.completeWineCount} of 6. '
          'Completion means observations were recorded, not that they were accurate.',
        ),
      ],
    );
  }

  Widget _comparison(D3TastingPaper paper) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Saved comparisons', style: Theme.of(context).textTheme.titleLarge),
      for (var index = 0; index < paper.comparisonPrompts.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
            key: ValueKey('d3-paper-comparison-$index'),
            controller: _editors['comparison:$index'],
            enabled: _editable,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: paper.kind == D3TastingPaperKind.grouped
                  ? 'Group ${index + 1} comparison'
                  : 'Six-wine comparison',
              helperText: paper.comparisonPrompts[index],
              helperMaxLines: 5,
            ),
            onChanged: (text) => _draft('comparison:$index', text),
          ),
        ),
      if (paper.isFinished) ...[
        Text(
          paper.isAbandoned
              ? 'Abandoned paper · no participation credit.'
              : '${paper.finishReason} · tasting responses are read-only.',
        ),
        if (!paper.readyToReview && !paper.isReviewed)
          const Text(
            'This incomplete paper can be inspected, but cannot count as reviewed six-wine participation.',
          ),
        TextField(
          key: const ValueKey('d3-paper-review'),
          controller: _editors['review'],
          enabled:
              !_busy &&
              !_writeFailed &&
              paper.readyToReview &&
              !paper.isReviewed,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: 'Post-paper self-review',
            helperText: paper.selfReviewPrompt,
            helperMaxLines: 5,
          ),
        ),
        TextButton(
          key: const ValueKey('d3-paper-save-review'),
          onPressed:
              !_busy &&
                  !_writeFailed &&
                  paper.readyToReview &&
                  !paper.isReviewed
              ? _review
              : null,
          child: const Text('Save self-review'),
        ),
        if (paper.isReviewed)
          const Text(
            'Self-reviewed timed practice recorded · no assessed score or pass.',
          ),
      ],
    ],
  );

  Widget _footer(D3TastingPaper paper) {
    final seconds = paper.remaining(_now).inSeconds;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              paper.isFinished
                  ? 'Paper ended · saved responses'
                  : 'Remaining ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, "0")}',
              key: const ValueKey('d3-paper-timer'),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('d3-paper-previous'),
                  onPressed: _busy || _step == 0 ? null : () => _go(_step - 1),
                  child: const Text('Previous'),
                ),
                Text(
                  _step < 6 ? 'Wine ${_step + 1} of 6' : 'Comparison',
                  key: const ValueKey('d3-paper-step'),
                ),
                TextButton(
                  key: const ValueKey('d3-paper-next'),
                  onPressed: _busy || _step == 6 ? null : () => _go(_step + 1),
                  child: const Text('Next'),
                ),
                if (!paper.isFinished) ...[
                  FilledButton(
                    key: const ValueKey('d3-paper-end'),
                    onPressed: _busy || _writeFailed ? null : () => _end(false),
                    child: const Text('End and review'),
                  ),
                  TextButton(
                    key: const ValueKey('d3-paper-abandon'),
                    onPressed: _busy || _writeFailed ? null : () => _end(true),
                    child: const Text('Abandon paper'),
                  ),
                ],
                if (paper.isFinished) ...[
                  TextButton(
                    key: const ValueKey('d3-paper-copy'),
                    onPressed: _busy ? null : _copyRecord,
                    child: const Text('Copy saved record'),
                  ),
                  TextButton(
                    key: const ValueKey('d3-paper-menu'),
                    onPressed: _busy ? null : _menu,
                    child: const Text('Practice menu'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave(result));
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Timed six-wine D3 practice'),
        leading: BackButton(
          key: const ValueKey('d3-paper-back'),
          onPressed: () => _leave(null),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.direction != ScrollDirection.idle) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const ValueKey('d3-paper-outer-scroll'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, key: const ValueKey('d3-paper-save-error')),
                      TextButton(
                        key: const ValueKey('d3-paper-reload'),
                        onPressed: _busy || _leaving ? null : _reload,
                        child: const Text('Reload saved practice'),
                      ),
                    ],
                    if (_paper == null)
                      _setup()
                    else ...[
                      Text(
                        '${_paper!.kind.name} · six neutral wine identifiers',
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          for (var index = 0; index < 6; index++)
                            TextButton(
                              key: ValueKey('d3-paper-nav-$index'),
                              onPressed: _busy ? null : () => _go(index),
                              child: Text('Wine ${index + 1}'),
                            ),
                          TextButton(
                            key: const ValueKey('d3-paper-nav-comparison'),
                            onPressed: _busy ? null : () => _go(6),
                            child: const Text('Compare / review'),
                          ),
                        ],
                      ),
                      if (_step < 6)
                        _wine(_paper!, _step)
                      else
                        _comparison(_paper!),
                    ],
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _paper == null ? null : _footer(_paper!),
    ),
  );
}

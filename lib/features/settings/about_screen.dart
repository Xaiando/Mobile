import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../core/database/app_database.dart';

/// About (backlog R1, GEO-14): what the app is and is not, the curriculum
/// release, and every source it draws on, with its licence and attribution.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _kinds = {
    'legislation': 'Legislation and official specifications',
    'regulator_register': 'Regulators\' registers',
    'government_publication': 'Government publications',
    'academic': 'Academic sources',
    'reference_work': 'Reference works',
    'dataset': 'Datasets',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final release = ref.watch(installedReleaseProvider).value;
    final sources = ref.watch(allSourcesProvider).value ?? const [];
    final byKind = <String, List<SourceCitation>>{};
    for (final source in sources) {
      byKind.putIfAbsent(source.kind, () => []).add(source);
    }

    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(text),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.wine_bar),
            title: const Text('Sommelier Study Companion'),
            subtitle: Text(
              release == null
                  ? 'Curriculum not installed yet'
                  : 'Curriculum release ${release.version}',
            ),
          ),
          heading('Please note'),
          paragraph(
            'WSET and CMS are named only to describe study tracks. This app '
            'is not affiliated with or endorsed by the Wine & Spirit '
            'Education Trust or the Court of Master Sommeliers, and it '
            'reproduces none of their exam questions, syllabus texts or '
            'tasting grids.',
          ),
          paragraph(
            'Curriculum content is drafted from public legal texts and other '
            'cited sources. It is marked unverified until a qualified '
            'reviewer checks it, and rules change: check the current '
            'official text before relying on a fact.',
          ),
          paragraph(
            'This app is for adults of legal drinking age. Please drink '
            'responsibly.',
          ),
          heading('Sources'),
          paragraph(
            'Every fact cites where it comes from. These are all the sources '
            'the curriculum uses.',
          ),
          for (final MapEntry(key: kind, value: list) in byKind.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                _kinds[kind] ?? kind,
                style: theme.textTheme.labelLarge,
              ),
            ),
            for (final source in list) _SourceTile(source),
          ],
          heading('Software'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Sommelier Study Companion',
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.source);

  final SourceCitation source;

  @override
  Widget build(BuildContext context) {
    final lines = [
      source.publisher,
      if (source.license case final license?) 'Licence: $license',
      ?source.attributionText,
      ?source.url,
    ];
    return ListTile(
      dense: true,
      title: Text(source.title),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
    );
  }
}

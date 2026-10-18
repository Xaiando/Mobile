import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/label_ai/label_ai_gateway.dart';
import '../../core/label_ai/label_ai_providers.dart';

/// Settings for the optional online label reader (docs/label-ai.md): the
/// learner's own API key, kept encrypted on the phone, and a switch.
class LabelAiSettingsSection extends ConsumerStatefulWidget {
  const LabelAiSettingsSection({super.key});

  @override
  ConsumerState<LabelAiSettingsSection> createState() =>
      _LabelAiSettingsSectionState();
}

class _LabelAiSettingsSectionState
    extends ConsumerState<LabelAiSettingsSection> {
  final _key = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(LabelAiGateway gateway) action,
  ) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action(ref.read(labelAiGatewayProvider));
      ref.invalidate(labelAiSettingsProvider);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _problem = '${error.message}');
    } catch (_) {
      if (mounted) {
        setState(() => _problem = 'The key could not be saved on this phone.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(labelAiSettingsProvider).value;
    final hasKey = settings?.hasKey ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional. In the wine editor, Read with online AI sends the '
            'photos of a label over the internet to Anthropic, whose service '
            'returns the producer, cuvée, region, grapes and vintage for you '
            'to confirm. It uses your own API key, so your Anthropic account '
            'is billed for each reading. Nothing is sent unless you tap that '
            'button, and the app works fully offline without it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'The key is kept encrypted by Android and is left out of exports '
            'and backups. While the app may use the network, Google’s '
            'on-device text recognition may also send usage statistics to '
            'Google.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (!hasKey) ...[
            TextField(
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Anthropic API key',
                errorText: _problem,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run((gateway) async {
                      await gateway.saveKey(_key.text);
                      _key.clear();
                    }),
              child: const Text('Save key'),
            ),
          ] else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Read labels with online AI'),
              subtitle: const Text('Adds a Read with online AI button.'),
              value: settings?.enabled ?? false,
              onChanged: _busy
                  ? null
                  : (value) => _run((gateway) => gateway.setEnabled(value)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run((gateway) => gateway.removeKey()),
                child: const Text('Remove key'),
              ),
            ),
            if (_problem != null)
              Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

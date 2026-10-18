import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:sommelier/core/label_ai/label_ai_client.dart';
import 'package:sommelier/core/label_ai/label_ai_gateway.dart';
import 'package:sommelier/core/label_ai/label_ai_providers.dart';
import 'package:sommelier/core/label_ai/secret_store.dart';
import 'package:sommelier/features/cellar/journal_scan_section.dart';
import 'package:sommelier/features/settings/label_ai_settings.dart';

class _QueuedPicker extends ImagePicker {
  _QueuedPicker(this._files);

  final List<XFile> _files;
  final sources = <ImageSource>[];

  @override
  bool supportsImageSource(ImageSource source) => true;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    sources.add(source);
    return _files.removeAt(0);
  }
}

XFile _photo(String name) => XFile.fromData(
  Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4))),
  path: name,
  mimeType: 'image/png',
);

http.Response _answer(Map<String, Object?> input) => http.Response(
  jsonEncode({
    'content': [
      {'type': 'tool_use', 'name': LabelAiClient.toolName, 'input': input},
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

LabelAiGateway _gateway(
  http.Client client, {
  bool enabled = true,
  bool consented = true,
}) => LabelAiGateway(
  MemorySecretStore({
    if (enabled) ...{
      LabelAiGateway.keyName: 'sk-ant-test-key-0000000000',
      LabelAiGateway.enabledName: '1',
    },
    if (consented) LabelAiGateway.consentName: '1',
  }),
  clientFor: (key) => LabelAiClient(apiKey: key, client: client),
);

Finder get _rawField => find.widgetWithText(
  TextField,
  'Recognized or manually transcribed label text',
);

Future<void> _show(
  WidgetTester tester, {
  required ImagePicker picker,
  required Future<String> Function(String) recognizeText,
  required LabelAiGateway gateway,
  void Function(String)? onProducer,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: JournalScanSection(
          picker: picker,
          recognizeText: recognizeText,
          labelAi: gateway,
          onPicked: (_, _) {},
          onVintage: (_) {},
          onNonVintage: () {},
          onAbv: (_) {},
          onProducer: onProducer,
          onAppellation: (_) {},
        ),
      ),
    ),
  ),
);

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void _scan(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

void main() {
  _scan('front and back photos are read together, online and on the phone', (
    tester,
  ) async {
    final seen = <Map<String, Object?>>[];
    final used = <String>[];
    await _show(
      tester,
      picker: _QueuedPicker([_photo('front.png'), _photo('back.png')]),
      recognizeText: (path) async =>
          path == 'front.png' ? 'CHATEAU EXEMPLE\nPAUILLAC' : 'ALC. 13.5% VOL.',
      gateway: _gateway(
        MockClient((request) async {
          seen.add(jsonDecode(request.body) as Map<String, Object?>);
          return _answer({
            'producer': 'Château Exemple',
            'appellation': 'Pauillac',
            'vintage': 2016,
          });
        }),
      ),
      onProducer: used.add,
    );

    await _tap(tester, 'Choose label');
    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Add back label'), findsOneWidget);
    expect(find.text('Read with online AI'), findsOneWidget);

    await _tap(tester, 'Add back label');
    expect(find.text('Back'), findsOneWidget);
    // The phone's own reading covers both photos.
    expect(
      tester.widget<TextField>(_rawField).controller!.text,
      'CHATEAU EXEMPLE\nPAUILLAC\nALC. 13.5% VOL.',
    );
    expect(find.text('Use 13.5% alcohol'), findsOneWidget);

    await _tap(tester, 'Read with online AI');
    final content =
        ((seen.single['messages']! as List).single as Map)['content'] as List;
    expect(
      content.where((block) => (block as Map)['type'] == 'image'),
      hasLength(2),
    );
    expect(find.text('Use producer Château Exemple'), findsOneWidget);
    expect(find.text('Use vintage 2016'), findsOneWidget);
    // The phone's clue and the online clues are offered together.
    expect(find.text('Use 13.5% alcohol'), findsOneWidget);

    await tester.tap(find.text('Use producer Château Exemple'));
    expect(used, ['Château Exemple']);
  });

  _scan('the first online reading asks before any photo leaves', (
    tester,
  ) async {
    var sent = 0;
    await _show(
      tester,
      picker: _QueuedPicker([_photo('front.png')]),
      recognizeText: (_) async => 'Estate',
      gateway: _gateway(
        MockClient((_) async {
          sent++;
          return _answer({'producer': 'Estate Test'});
        }),
        consented: false,
      ),
      onProducer: (_) {},
    );
    await _tap(tester, 'Choose label');

    await _tap(tester, 'Read with online AI');
    expect(find.text('Send these photos?'), findsOneWidget);
    await _tap(tester, 'Cancel');
    expect(sent, 0);
    expect(find.text('Use producer Estate Test'), findsNothing);

    await _tap(tester, 'Read with online AI');
    await _tap(tester, 'Send');
    expect(sent, 1);
    expect(find.text('Use producer Estate Test'), findsOneWidget);

    // Agreed once: the next reading goes straight through.
    await _tap(tester, 'Read with online AI');
    expect(find.text('Send these photos?'), findsNothing);
    expect(sent, 2);
  });

  _scan('when the online reader fails, the phone\'s reading stays', (
    tester,
  ) async {
    await _show(
      tester,
      picker: _QueuedPicker([_photo('front.png')]),
      recognizeText: (_) async => 'Estate 2019 13.5%',
      gateway: _gateway(MockClient((_) async => http.Response('{}', 500))),
    );
    await _tap(tester, 'Choose label');
    await _tap(tester, 'Read with online AI');
    expect(find.textContaining('online reader had a problem'), findsOneWidget);
    expect(find.text('Use vintage 2019'), findsOneWidget);
    expect(find.text('Use 13.5% alcohol'), findsOneWidget);
  });

  _scan('with the reader switched off, the button points to Settings', (
    tester,
  ) async {
    var sent = 0;
    await _show(
      tester,
      picker: _QueuedPicker([_photo('front.png')]),
      recognizeText: (_) async => '',
      gateway: _gateway(
        MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
        enabled: false,
      ),
    );
    await _tap(tester, 'Choose label');
    await _tap(tester, 'Read with online AI');
    expect(find.textContaining('under Label reading'), findsOneWidget);
    expect(sent, 0);
  });

  _scan('a new label starts a new scan', (tester) async {
    await _show(
      tester,
      picker: _QueuedPicker([
        _photo('a-front.png'),
        _photo('a-back.png'),
        _photo('b-front.png'),
      ]),
      recognizeText: (_) async => 'Estate',
      gateway: _gateway(MockClient((_) async => http.Response('{}', 500))),
    );
    await _tap(tester, 'Choose label');
    await _tap(tester, 'Add back label');
    expect(find.text('Back'), findsOneWidget);
    await _tap(tester, 'Choose label');
    expect(find.text('Back'), findsNothing);
    expect(find.text('Front'), findsOneWidget);
  });

  group('settings', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      MemorySecretStore store,
    ) async {
      final container = ProviderContainer(
        overrides: [secretStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LabelAiSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('saves a key, switches the reader, and removes the key', (
      tester,
    ) async {
      final store = MemorySecretStore();
      await pump(tester, store);

      await tester.enterText(find.byType(TextField), 'too short');
      await tester.tap(find.text('Save key'));
      await tester.pump();
      await tester.pump();
      expect(find.text('That is too short to be an API key.'), findsOneWidget);
      expect(await store.read(LabelAiGateway.keyName), isNull);

      await tester.enterText(
        find.byType(TextField),
        'sk-ant-test-key-0000000000',
      );
      await tester.tap(find.text('Save key'));
      await tester.pump();
      await tester.pump();
      expect(
        await store.read(LabelAiGateway.keyName),
        'sk-ant-test-key-0000000000',
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.pump();
      expect(await store.read(LabelAiGateway.enabledName), '0');

      await tester.tap(find.text('Remove key'));
      await tester.pump();
      await tester.pump();
      expect(await store.read(LabelAiGateway.keyName), isNull);
      expect(find.text('Save key'), findsOneWidget);
    });
  });
}

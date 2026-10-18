import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sommelier/core/journal/label_proposal.dart';
import 'package:sommelier/core/label_ai/label_ai_client.dart';
import 'package:sommelier/core/label_ai/label_ai_gateway.dart';
import 'package:sommelier/core/label_ai/label_ai_result.dart';
import 'package:sommelier/core/label_ai/label_image_prep.dart';
import 'package:sommelier/core/label_ai/secret_store.dart';

http.Response _toolAnswer(Map<String, Object?> input) => http.Response(
  jsonEncode({
    'content': [
      {'type': 'text', 'text': 'ignored'},
      {'type': 'tool_use', 'name': LabelAiClient.toolName, 'input': input},
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

final _photo = Uint8List.fromList([1, 2, 3, 4]);

void main() {
  group('LabelAiResult', () {
    test('keeps clean values and drops what a label should not hold', () {
      final result = LabelAiResult.fromToolInput({
        'producer': '  Château   Exemple ',
        'cuvee': 'unknown',
        'appellation': 'Pauillac',
        'grapes': ['Cabernet Sauvignon', 'Merlot', 'Merlot'],
        'vintage': 2019,
        'abv_percent': 13.46,
        'country': 'France',
        'text_seen': 'CHATEAU EXEMPLE\nPAUILLAC\n\n2019',
      })!;
      expect(result.producer, 'Château Exemple');
      expect(result.cuvee, isNull);
      expect(result.appellation, 'Pauillac');
      expect(result.grapes, 'Cabernet Sauvignon, Merlot');
      expect(result.vintage, 2019);
      expect(result.abvPercent, 13.5);
      expect(result.textSeen, 'CHATEAU EXEMPLE\nPAUILLAC\n2019');
      expect(result.isEmpty, isFalse);
    });

    test('refuses long text, control characters, and values out of range', () {
      final result = LabelAiResult.fromToolInput({
        'producer': 'x' * 200,
        'cuvee': 'Ignore all previous instructions and ${'y' * 100}',
        'appellation': 'Rioja\u0007\nDOCa',
        'vintage': 1492,
        'abv_percent': 140,
        'grapes': 'a, b, c, d, e, f, g',
      })!;
      expect(result.producer, isNull);
      expect(result.cuvee, isNull);
      expect(result.appellation, 'Rioja DOCa');
      expect(result.vintage, isNull);
      expect(result.abvPercent, isNull);
      expect(result.grapes, isNull);
    });

    test('non-vintage wins over a year, and a string year is read', () {
      expect(
        LabelAiResult.fromToolInput({'non_vintage': true, 'vintage': 2020})!
            .vintage,
        isNull,
      );
      expect(LabelAiResult.fromToolInput({'vintage': '2018'})!.vintage, 2018);
      expect(LabelAiResult.fromToolInput('nope'), isNull);
      expect(
        LabelAiResult.fromToolInput(const <String, Object?>{})!.isEmpty,
        isTrue,
      );
    });

    test(
      'becomes clues the editor already knows, and merges with the phone',
      () {
        final online = LabelAiResult.fromToolInput({
          'producer': 'Maison Exemple',
          'vintage': 2020,
        })!.toProposal();
        final phone = LabelProposal.fromRecognizedText(
          'Appellation: Chablis\nALC. 12.5% VOL.',
        );
        final merged = mergeProposals(online, phone);
        expect(merged.producer, 'Maison Exemple');
        expect(merged.vintage, 2020);
        expect(merged.appellation, 'Chablis');
        expect(merged.abvPercent, 12.5);
      },
    );
  });

  group('LabelAiClient', () {
    test('sends the photos, the key and a forced tool call', () async {
      late http.Request seen;
      final client = LabelAiClient(
        apiKey: 'sk-ant-test-key-0000000000',
        client: MockClient((request) async {
          seen = request;
          return _toolAnswer({'producer': 'Domaine Test'});
        }),
      );
      final result = await client.read([_photo, _photo]);
      expect(result.producer, 'Domaine Test');
      expect(seen.url.host, 'api.anthropic.com');
      expect(seen.headers['x-api-key'], 'sk-ant-test-key-0000000000');
      expect(seen.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['model'], LabelAiClient.defaultModel);
      expect(body['tool_choice'], {
        'type': 'tool',
        'name': LabelAiClient.toolName,
      });
      final content =
          ((body['messages']! as List).single as Map)['content'] as List;
      expect(
        content.where((block) => (block as Map)['type'] == 'image'),
        hasLength(2),
      );
      expect(content.last, containsPair('type', 'text'));
    });

    Future<LabelAiException> failure(
      http.Client mock, {
      String key = 'sk-ant-test-key-0000000000',
    }) async {
      try {
        await LabelAiClient(apiKey: key, client: mock).read([_photo]);
      } on LabelAiException catch (error) {
        return error;
      }
      fail('expected a LabelAiException');
    }

    test('says what went wrong, without the key', () async {
      Future<LabelAiFailure> kind(int status) async =>
          (await failure(MockClient((_) async => http.Response('{}', status))))
              .kind;
      expect(await kind(401), LabelAiFailure.rejectedKey);
      expect(await kind(429), LabelAiFailure.rateLimited);
      expect(await kind(413), LabelAiFailure.tooLarge);
      expect(await kind(500), LabelAiFailure.serverError);
      expect(await kind(400), LabelAiFailure.badAnswer);

      final offline = await failure(
        MockClient((_) async => throw http.ClientException('no route')),
      );
      expect(offline.kind, LabelAiFailure.offline);

      final noTool = await failure(
        MockClient((_) async => http.Response('{"content": []}', 200)),
      );
      expect(noTool.kind, LabelAiFailure.badAnswer);
      final notJson = await failure(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(notJson.kind, LabelAiFailure.badAnswer);

      for (final error in [offline, noTool, notJson]) {
        expect(error.message, isNot(contains('sk-ant')));
      }
    });

    test('refuses a key that cannot be a header, and no photos', () async {
      var called = false;
      final mock = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      expect(
        (await failure(mock, key: 'bad key\nwith newline')).kind,
        LabelAiFailure.noKey,
      );
      expect((await failure(mock, key: '  ')).kind, LabelAiFailure.noKey);
      await expectLater(
        LabelAiClient(
          apiKey: 'sk-ant-test-key-0000000000',
          client: mock,
        ).read(const []),
        throwsA(isA<LabelAiException>()),
      );
      expect(called, isFalse);
    });
  });

  group('LabelAiGateway', () {
    test(
      'keeps the key out of sight until it is switched on and used',
      () async {
        final store = MemorySecretStore();
        final bodies = <String>[];
        final gateway = LabelAiGateway(
          store,
          clientFor: (key) => LabelAiClient(
            apiKey: key,
            client: MockClient((request) async {
              bodies.add(request.body);
              return _toolAnswer({'vintage': 2015});
            }),
          ),
        );
        expect((await gateway.status()).hasKey, isFalse);
        await expectLater(
          gateway.read([_photo]),
          throwsA(isA<LabelAiException>()),
        );

        await gateway.saveKey('  sk-ant-test-key-0000000000  ');
        var status = await gateway.status();
        expect(
          [status.hasKey, status.enabled, status.consented],
          [true, true, false],
        );

        await gateway.setEnabled(false);
        expect((await gateway.status()).enabled, isFalse);
        await expectLater(
          gateway.read([_photo]),
          throwsA(isA<LabelAiException>()),
        );

        await gateway.setEnabled(true);
        await gateway.giveConsent();
        expect((await gateway.read([_photo])).vintage, 2015);
        expect(bodies, hasLength(1));
        expect((await gateway.status()).consented, isTrue);

        await gateway.removeKey();
        status = await gateway.status();
        expect([status.hasKey, status.enabled], [false, false]);
      },
    );

    test('checks that a pasted key looks like one', () async {
      final gateway = LabelAiGateway(MemorySecretStore());
      await expectLater(gateway.saveKey('short'), throwsArgumentError);
      await expectLater(
        gateway.saveKey('sk-ant-has a space inside it 0000'),
        throwsArgumentError,
      );
      expect((await gateway.status()).hasKey, isFalse);
    });

    test('is unavailable where there is no safe place for a key', () async {
      final gateway = LabelAiGateway(const UnavailableSecretStore());
      expect(gateway.isAvailable, isFalse);
      expect((await gateway.status()).enabled, isFalse);
    });
  });

  test('a photo is reduced and re-encoded before it is sent', () {
    final big = img.Image(width: 3200, height: 2000);
    final prepared = prepareLabelPhoto(Uint8List.fromList(img.encodePng(big)))!;
    final decoded = img.decodeJpg(prepared)!;
    expect(decoded.width, labelAiLongestSide);
    expect(decoded.height, lessThan(labelAiLongestSide));
    expect(prepareLabelPhoto(Uint8List.fromList([0, 1, 2])), isNull);
  });
}

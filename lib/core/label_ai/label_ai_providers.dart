import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'label_ai_gateway.dart';
import 'label_image_prep.dart';
import 'secret_store.dart';

/// The learner's key, kept by Android's Keystore (android/.../SecretVault.kt).
/// Only the app's private storage holds the encrypted value, and the backup
/// rules leave it out.
class AndroidSecretStore implements SecretStore {
  const AndroidSecretStore([
    this._channel = const MethodChannel('com.xaiando.sommelier/secrets'),
  ]);

  final MethodChannel _channel;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> read(String name) async {
    try {
      return await _channel.invokeMethod<String>('read', {'name': name});
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(String name, String value) =>
      _channel.invokeMethod<void>('write', {'name': name, 'value': value});

  @override
  Future<void> delete(String name) =>
      _channel.invokeMethod<void>('delete', {'name': name});
}

bool get _onAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final secretStoreProvider = Provider<SecretStore>(
  (ref) =>
      _onAndroid ? const AndroidSecretStore() : const UnavailableSecretStore(),
);

final labelAiGatewayProvider = Provider<LabelAiGateway>(
  (ref) => LabelAiGateway(
    ref.watch(secretStoreProvider),
    prepare: (photo) => compute(prepareLabelPhoto, photo),
  ),
);

/// The learner's current choices; invalidate it after changing them.
final labelAiSettingsProvider = FutureProvider<LabelAiSettings>(
  (ref) => ref.watch(labelAiGatewayProvider).status(),
);

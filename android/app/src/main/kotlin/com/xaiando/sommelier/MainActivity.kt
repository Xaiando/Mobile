package com.xaiando.sommelier

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val vault = SecretVault(applicationContext)
        // The learner's API key for the online label reader
        // (lib/core/label_ai/label_ai_providers.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECRETS)
            .setMethodCallHandler { call, result ->
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("bad_args", "A name is required.", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "read" -> result.success(vault.read(name))
                        "write" -> {
                            val value = call.argument<String>("value")
                            if (value == null) {
                                result.error("bad_args", "A value is required.", null)
                            } else {
                                vault.write(name, value)
                                result.success(null)
                            }
                        }
                        "delete" -> {
                            vault.delete(name)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("vault_failed", error.javaClass.simpleName, null)
                }
            }
    }

    companion object {
        private const val SECRETS = "com.xaiando.sommelier/secrets"
    }
}

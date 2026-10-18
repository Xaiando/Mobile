package com.xaiando.sommelier

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps a few small secrets, today the learner's API key for the online label
 * reader. Each value is encrypted with an AES-GCM key that never leaves
 * Android's Keystore, and only the ciphertext is written to the app's private
 * preferences. The backup rules leave that file out, so a restore on another
 * phone could not read it anyway.
 */
class SecretVault(context: Context) {
    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    fun write(name: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(sealed, Base64.NO_WRAP)
        prefs.edit().putString(name, stored).apply()
    }

    /** The value, or null when there is none or it can no longer be read. */
    fun read(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        return try {
            val parts = stored.split(":")
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val sealed = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(sealed), Charsets.UTF_8)
        } catch (error: Exception) {
            // A key the Keystore lost, or a damaged value: forget it, so the
            // learner is asked for the key again instead of failing for ever.
            prefs.edit().remove(name).apply()
            null
        }
    }

    fun delete(name: String) {
        prefs.edit().remove(name).apply()
    }

    companion object {
        const val FILE = "secret_vault"
        private const val ALIAS = "sommelier_secret_vault"
        private const val TRANSFORM = "AES/GCM/NoPadding"
    }
}

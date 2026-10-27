import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinVaultException implements Exception {
  const PinVaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Device-only quick unlock. With a PIN set, the login session is stored only encrypted
/// (AES-256-GCM, key = PBKDF2-SHA256(PIN, random salt)). The PIN itself is never stored or sent anywhere.
/// Without a PIN it behaves like the default Supabase storage.
class PinVault extends LocalStorage {
  PinVault(this._plainKey);

  final String _plainKey;
  static const _encKey = 'fs_pin_session';
  static const _saltKey = 'fs_pin_salt';
  static const _failKey = 'fs_pin_fails';
  static const _deviceKey = 'fs_device_id';
  static const _methodKey = 'fs_unlock_method';
  static const maxAttempts = 5;

  static SharedPreferences? _prefs;
  static SecretKey? _key;
  static String? _pending;
  static String _plainKeyName = '';
  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256);

  static bool get pinEnabled => _prefs?.containsKey(_encKey) ?? false;
  static bool get locked => pinEnabled && _key == null;
  static String? get deviceId => _prefs?.getString(_deviceKey);
  static int get failures => _prefs?.getInt(_failKey) ?? 0;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _plainKeyName = _plainKey;
  }

  @override
  Future<bool> hasAccessToken() async => pinEnabled ? _key != null : _prefs!.containsKey(_plainKey);

  @override
  Future<String?> accessToken() async =>
      pinEnabled ? (_key == null ? null : _decrypt(_key!)) : _prefs!.getString(_plainKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (!pinEnabled) {
      await _prefs!.setString(_plainKey, persistSessionString);
    } else if (_key != null) {
      await _prefs!.setString(_encKey, await _encrypt(_key!, persistSessionString));
    } else {
      _pending = persistSessionString; // refreshed while locked; saved encrypted on next unlock
    }
  }

  @override
  Future<void> removePersistedSession() async {
    await _prefs!.remove(_plainKey);
    await clearPin();
  }

  /// Encrypts the current session under [pin] and removes the plain copy.
  static Future<void> enablePin(String pin, String sessionJson, String deviceId) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    await _prefs!.setString(_saltKey, base64Encode(salt));
    await _prefs!.setString(_encKey, await _encrypt(key, sessionJson));
    await _prefs!.setString(_deviceKey, deviceId);
    await _prefs!.setString(_methodKey, 'pin');
    await _prefs!.remove(_failKey);
    await _prefs!.remove(_plainKeyName);
    _key = key;
  }

  /// Returns the decrypted session; wipes the saved login after [maxAttempts] wrong PINs.
  static Future<String> unlock(String pin) async {
    if (!pinEnabled) throw const PinVaultException('No PIN on this device. Log in with an email code.');
    final key = await _kdf.deriveKeyFromPassword(password: pin, nonce: base64Decode(_prefs!.getString(_saltKey)!));
    try {
      final session = await _decrypt(key);
      _key = key;
      await _prefs!.remove(_failKey);
      if (_pending != null) {
        await _prefs!.setString(_encKey, await _encrypt(key, _pending!));
        _pending = null;
      }
      return session;
    } on SecretBoxAuthenticationError {
      final fails = failures + 1;
      if (fails >= maxAttempts) {
        await clearPin();
        throw const PinVaultException('Too many wrong PINs. Log in with an email code.');
      }
      await _prefs!.setInt(_failKey, fails);
      throw PinVaultException('Wrong PIN. ${maxAttempts - fails} attempts left.');
    }
  }

  /// Locks without signing out (idle timeout); the PIN is needed again.
  static void lockNow() => _key = null;

  /// Turns quick unlock off, keeping the user logged in on this device.
  static Future<void> disablePin(String? currentSessionJson) async {
    await clearPin();
    if (currentSessionJson != null) await _prefs!.setString(_plainKeyName, currentSessionJson);
  }

  static Future<void> clearPin() async {
    for (final k in [_encKey, _saltKey, _failKey, _deviceKey, _methodKey]) {
      await _prefs?.remove(k);
    }
    _key = null;
    _pending = null;
  }

  static Future<String> _encrypt(SecretKey key, String plain) async =>
      base64Encode((await _aes.encryptString(plain, secretKey: key)).concatenation());

  static Future<String> _decrypt(SecretKey key) async => _aes.decryptString(
    SecretBox.fromConcatenation(base64Decode(_prefs!.getString(_encKey)!), nonceLength: 12, macLength: 16),
    secretKey: key,
  );
}

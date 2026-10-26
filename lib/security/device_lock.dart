import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../backend/backend.dart' show backendEnabled;
import '../state/app_state.dart';
import 'web_biometric.dart' as web_bio;

enum LockStatus { unlocked, locked, needsSetup }

/// PIN hash and the biometric on/off flag stay in this device's secure storage; the biometric itself is checked by the OS.
class DeviceLock {
  static const _store = FlutterSecureStorage();
  static final _auth = LocalAuthentication();
  static const maxAttempts = 5;

  static Future<bool> hasPin() async => await _store.read(key: 'pin_hash') != null;

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> setPin(String pin, String owner) async {
    await _store.write(key: 'pin_owner', value: owner);
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await _store.write(key: 'pin_salt', value: salt);
    await _store.write(key: 'pin_hash', value: _hash(pin, salt));
    await _store.write(key: 'pin_fails', value: '0');
  }

  /// Returns -1 when the PIN is correct, otherwise the attempts left (0 means locked out).
  static Future<int> verifyPin(String pin) async {
    final salt = await _store.read(key: 'pin_salt') ?? '';
    final stored = await _store.read(key: 'pin_hash');
    if (stored != null && stored == _hash(pin, salt)) {
      await _store.write(key: 'pin_fails', value: '0');
      return -1;
    }
    final fails = (int.tryParse(await _store.read(key: 'pin_fails') ?? '') ?? 0) + 1;
    await _store.write(key: 'pin_fails', value: '$fails');
    return max(0, maxAttempts - fails);
  }

  static Future<bool> biometricAvailable() async {
    if (kIsWeb) return web_bio.webBiometricAvailable();
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> biometricEnabled() async => await _store.read(key: 'bio_enabled') == '1';

  static Future<void> setBiometricEnabled(bool on) => _store.write(key: 'bio_enabled', value: on ? '1' : '0');

  static Future<String?> pinOwner() => _store.read(key: 'pin_owner');

  static Future<bool> enrollBiometric(String label) =>
      kIsWeb ? web_bio.webBiometricRegister(label) : authenticateBiometric('Confirm to enable biometric unlock');

  static Future<bool> authenticateBiometric(String reason) async {
    if (kIsWeb) return web_bio.webBiometricVerify();
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    for (final key in const ['pin_hash', 'pin_salt', 'pin_fails', 'bio_enabled', 'pin_owner']) {
      await _store.delete(key: key);
    }
  }
}

final lockProvider = NotifierProvider<LockNotifier, LockStatus>(LockNotifier.new);

class LockNotifier extends Notifier<LockStatus> {
  @override
  LockStatus build() {
    ref.listen(sessionProvider, (prev, next) async {
      if (next == null) {
        state = LockStatus.unlocked;
      } else if (prev == null && backendEnabled) {
        state = LockStatus.locked;
        await _resolve(fresh: true);
      }
    });
    if (backendEnabled && ref.read(sessionProvider) != null) {
      Future.microtask(_resolve);
      return LockStatus.locked;
    }
    return LockStatus.unlocked;
  }

  /// A fresh OTP sign-in already proved identity, so a PIN set earlier on this device is not asked again.
  Future<void> _resolve({bool fresh = false}) async {
    final uid = ref.read(sessionProvider)?.user.id;
    if (uid == null) return;
    final owner = await DeviceLock.pinOwner();
    if (owner != null && owner != uid) await DeviceLock.clear();
    if (!await DeviceLock.hasPin()) {
      state = LockStatus.needsSetup;
    } else {
      state = fresh ? LockStatus.unlocked : LockStatus.locked;
    }
  }

  void unlock() => state = LockStatus.unlocked;
}

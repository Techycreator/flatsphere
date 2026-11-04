import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../backend/backend.dart' show backendEnabled;
import '../state/app_state.dart';
import 'web_biometric.dart' as web_bio;

enum LockStatus { unlocked, locked, needsSetup }

/// Only the biometric on/off flag and its owner are kept in this device's secure storage; the fingerprint or face itself
/// is checked by the phone or browser and never reaches the app or the database.
class DeviceLock {
  static const _store = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  static Future<bool> biometricAvailable() async {
    if (kIsWeb) return web_bio.webBiometricAvailable();
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> biometricEnabled() async => await _store.read(key: 'bio_enabled') == '1';

  static Future<void> enableBiometric(String owner) async {
    await _store.write(key: 'pin_owner', value: owner);
    await _store.delete(key: 'pin_skip_owner');
    await _store.write(key: 'bio_enabled', value: '1');
  }

  static Future<String?> owner() => _store.read(key: 'pin_owner');

  static Future<bool> hasLegacyPin() async =>
      await _store.read(key: 'pin_hash') != null || await _store.read(key: 'pin_salt') != null;

  static Future<bool> enrollBiometric(String label) => kIsWeb
      ? web_bio.webBiometricRegister(label)
      : authenticateBiometric('Confirm to turn on fingerprint / face unlock');

  static Future<bool> authenticateBiometric(String reason) async {
    if (kIsWeb) return web_bio.webBiometricVerify();
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> skippedBy(String uid) async => await _store.read(key: 'pin_skip_owner') == uid;

  static Future<void> skip(String uid) => _store.write(key: 'pin_skip_owner', value: uid);

  static Future<void> clear() async {
    for (final key in const ['bio_enabled', 'pin_owner']) {
      await _store.delete(key: key);
    }
  }

  static Future<void> removeLegacyPin() async {
    for (final key in const ['pin_hash', 'pin_salt', 'pin_fails']) {
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

  /// A fresh OTP sign-in already proved identity, so fingerprint / face is not asked again right after it.
  Future<void> _resolve({bool fresh = false}) async {
    final uid = ref.read(sessionProvider)?.user.id;
    if (uid == null) return;
    if (fresh) {
      await DeviceLock.removeLegacyPin();
    } else if (await DeviceLock.hasLegacyPin()) {
      state = LockStatus.locked;
      return;
    }
    final owner = await DeviceLock.owner();
    if (owner != null && owner != uid) await DeviceLock.clear();
    if (await DeviceLock.biometricEnabled()) {
      state = fresh ? LockStatus.unlocked : LockStatus.locked;
    } else if (!await DeviceLock.skippedBy(uid) && await DeviceLock.biometricAvailable()) {
      state = LockStatus.needsSetup;
    } else {
      state = LockStatus.unlocked;
    }
  }

  void unlock() => state = LockStatus.unlocked;
}

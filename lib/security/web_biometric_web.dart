import 'dart:js_interop';

@JS('flatsphereBiometric')
external _Bio get _bio;

extension type _Bio._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> available();
  external JSPromise<JSBoolean> register(String label);
  external JSPromise<JSBoolean> verify();
}

Future<bool> _run(JSPromise<JSBoolean> Function() call) async {
  try {
    return (await call().toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<bool> webBiometricAvailable() => _run(() => _bio.available());

Future<bool> webBiometricRegister(String label) => _run(() => _bio.register(label));

Future<bool> webBiometricVerify() => _run(() => _bio.verify());

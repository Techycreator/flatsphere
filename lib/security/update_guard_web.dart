import 'dart:js_interop';

@JS('flatsphereUpdateGuard')
external _Guard? get _guard;

extension type _Guard._(JSObject _) implements JSObject {
  external void hold();
  external void release();
}

/// Holds back the "Update available" overlay while [action] runs, so a reload cannot interrupt it
/// (for example a payment waiting for the gateway). The prompt appears once the action finishes.
Future<T> runWithoutUpdatePrompt<T>(Future<T> Function() action) async {
  final guard = _guard;
  guard?.hold();
  try {
    return await action();
  } finally {
    guard?.release();
  }
}

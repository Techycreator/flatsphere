import 'dart:convert';
import 'dart:js_interop';

@JS('flatspherePush')
external _Push? get _push;

extension type _Push._(JSObject _) implements JSObject {
  external JSPromise<JSString?> subscribe(JSString key);
}

/// Asks the browser for notification permission and returns this device's push subscription.
Future<({String endpoint, String p256dh, String auth})?> subscribeWebPush(String vapidKey) async {
  final p = _push;
  if (p == null) return null;
  final raw = (await p.subscribe(vapidKey.toJS).toDart)?.toDart;
  if (raw == null) return null;
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final keys = j['keys'] as Map<String, dynamic>;
  return (endpoint: j['endpoint'] as String, p256dh: keys['p256dh'] as String, auth: keys['auth'] as String);
}

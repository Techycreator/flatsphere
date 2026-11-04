import 'dart:js_interop';
import 'dart:typed_data';

@JS('flatsphereOcr')
external JSPromise<JSString?> _ocr(JSUint8Array bytes);

/// Reads the text on a bill photo in the browser (Tesseract.js, loaded on first use); nothing is sent to our servers.
Future<String?> readBillText(Uint8List bytes) async {
  try {
    return (await _ocr(bytes.toJS).toDart)?.toDart;
  } catch (_) {
    return null;
  }
}

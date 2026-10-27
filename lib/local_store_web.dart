import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String? readLocal(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeLocal(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

String readRoute() => Uri.decodeComponent(
  web.window.location.hash.replaceFirst(RegExp(r'^#/?'), ''),
);
void writeRoute(String route) {
  web.window.location.hash = '/${Uri.encodeComponent(route)}';
}

Stream<String> get routeChanges => Stream<String>.multi((controller) {
  final callback = ((web.Event event) => controller.add(readRoute())).toJS;
  web.window.addEventListener('hashchange', callback);
  controller.onCancel = () =>
      web.window.removeEventListener('hashchange', callback);
});
bool downloadBytes(Uint8List bytes, String filename) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
  return true;
}

bool openWebsite(String url) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener noreferrer';
  anchor.click();
  return true;
}

String? readSession(String key) {
  try {
    return web.window.sessionStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeSession(String key, String? value) {
  try {
    if (value == null) {
      web.window.sessionStorage.removeItem(key);
    } else {
      web.window.sessionStorage.setItem(key, value);
    }
  } catch (_) {}
}

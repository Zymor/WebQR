import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<Map<String, dynamic>?> pickPhoto() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,image/webp';
  final done = Completer<Map<String, dynamic>?>();
  Future<void> read() async {
    try {
      final file = input.files?.item(0);
      if (file == null) {
        done.complete(null);
        return;
      }
      if (file.size > 2097152) {
        throw Exception('Choose a photo of 2 MB or smaller.');
      }
      if (!['image/jpeg', 'image/png', 'image/webp'].contains(file.type)) {
        throw Exception('Choose a JPEG, PNG or WebP photo.');
      }
      final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
      done.complete({'bytes': bytes, 'mime': file.type});
    } catch (e) {
      done.completeError(e);
    }
  }

  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!done.isCompleted) {
        done.complete(null);
      }
    }).toJS,
  );
  input.addEventListener(
    'change',
    ((web.Event _) {
      unawaited(read());
    }).toJS,
  );
  input.click();
  return done.future;
}

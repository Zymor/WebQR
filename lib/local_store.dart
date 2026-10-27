import 'dart:typed_data';

String? readLocal(String key) => null;
void writeLocal(String key, String value) {}
String readRoute() => '';
void writeRoute(String route) {}
Stream<String> get routeChanges => const Stream.empty();
bool downloadBytes(Uint8List bytes, String filename) => false;

bool openWebsite(String url) => false;

String? readSession(String key) => null;
void writeSession(String key, String? value) {}

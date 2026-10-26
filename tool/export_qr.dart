import 'dart:convert';
import 'dart:io';

import 'package:qr/qr.dart';

Future<void> main(List<String> args) async {
  final api = args.isEmpty ? 'http://127.0.0.1:8787/api' : args.first;
  final client = HttpClient();
  final response = await (await client.getUrl(Uri.parse('$api/tables')))
      .close();
  final data = jsonDecode(await utf8.decodeStream(response));
  client.close();
  final base = (data['website_url'] as String).replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) {
    throw StateError('Set the website URL in Tables before exporting.');
  }
  final folder = Directory('qr-codes')..createSync();
  final cards = <String>[];
  const escape = HtmlEscape();
  for (final table in data['tables'] as List) {
    if (table['active'] != 1) continue;
    final link = '$base/#/Table:${table['id']}';
    final qr = QrImage(
      QrCode.fromData(data: link, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final side = qr.moduleCount + 8;
    final blocks = StringBuffer();
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var col = 0; col < qr.moduleCount; col++) {
        if (qr.isDark(row, col)) {
          blocks.write(
            '<rect x="${col + 4}" y="${row + 4}" width="1" height="1"/>',
          );
        }
      }
    }
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $side $side" shape-rendering="crispEdges"><rect width="$side" height="$side" fill="white"/><g fill="black">$blocks</g></svg>';
    File('${folder.path}/after-work-${table['id']}.svg').writeAsStringSync(svg);
    cards.add(
      '<article><header>AFTER WORK</header>$svg<h2>${escape.convert(table['name'])}</h2><p>SCAN TO EXPLORE THE MENU</p><a href="${escape.convert(link)}">${escape.convert(link)}</a></article>',
    );
  }
  File('${folder.path}/after-work-tables.html').writeAsStringSync(
    '''<!doctype html><html lang="en"><meta charset="utf-8"><title>After Work — Table QR Cards</title><style>body{font-family:Arial,sans-serif;background:#f5f3ed;color:#142d29;margin:32px}h1{font-family:Georgia,serif}main{display:grid;grid-template-columns:repeat(3,1fr);gap:24px}article{background:white;padding:26px;text-align:center;border:1px solid #ddd9cf;border-radius:8px;break-inside:avoid}header{letter-spacing:5px;font-size:17px;font-weight:bold}svg{width:100%;max-width:280px;margin-top:20px}h2{font-family:Georgia,serif;font-size:30px;margin:8px}p{font-size:10px;letter-spacing:2px}a{color:#777;font-size:9px;word-break:break-all}button{background:#142d29;color:white;border:0;border-radius:5px;padding:14px 24px;margin-bottom:24px;cursor:pointer}@media(max-width:800px){main{grid-template-columns:repeat(2,1fr)}}@media print{body{background:white;margin:0}h1,.note,button{display:none}main{grid-template-columns:repeat(2,1fr);gap:10mm}article{padding:10mm;border:1px dashed #aaa}svg{max-width:65mm}}</style><h1>After Work · One table, one QR.</h1><p class="note">These codes use ${escape.convert(base)}. Phones must be on the same Wi-Fi for a local network address. Keep the web and API servers running. Reprint codes if your website address changes.</p><button onclick="window.print()">Print table cards</button><main>${cards.join()}</main></html>''',
  );
  stdout.writeln(
    'Exported ${cards.length} individual QR codes and printable cards to ${folder.absolute.path}.',
  );
}

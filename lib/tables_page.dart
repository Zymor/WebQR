import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'service_pages.dart';
import 'local_store.dart' if (dart.library.js_interop) 'local_store_web.dart';

class TablesPage extends StatefulWidget {
  const TablesPage({super.key});
  @override
  State<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends State<TablesPage> {
  List<dynamic>? tables;
  final website = TextEditingController();
  String message = '';
  bool busy = false;
  bool get manager =>
      Api.user != null &&
      ['super_admin', 'manager'].contains(Api.user!['role']);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    website.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final response = await Api.request('/tables');
      if (mounted) {
        setState(() {
          tables = response['tables'];
          website.text = response['website_url'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  String link(dynamic table) =>
      '${website.text.trim().replaceAll(RegExp(r'/+$'), '')}/#/Table:${table['id']}';
  Future<void> saveUrl() async {
    setState(() => busy = true);
    try {
      final url = Uri.tryParse(website.text.trim());
      if (url == null ||
          !['http', 'https'].contains(url.scheme) ||
          url.host.isEmpty ||
          url.hasFragment ||
          url.hasQuery) {
        throw Exception(
          'Enter the website address without a fragment or query.',
        );
      }
      await Api.request(
        '/admin/settings',
        method: 'PATCH',
        data: {
          'website_url': website.text.trim().replaceAll(RegExp(r'/+$'), ''),
        },
      );
      if (mounted) {
        setState(
          () =>
              message = 'Website address saved. QR codes now use this address.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([dynamic table]) async {
    final id = TextEditingController(
      text:
          table?['id'] ??
          'T${((tables?.length ?? 0) + 1).toString().padLeft(2, '0')}',
    );
    final name = TextEditingController(
      text:
          table?['name'] ??
          'Table ${((tables?.length ?? 0) + 1).toString().padLeft(2, '0')}',
    );
    final seats = TextEditingController(text: '${table?['seats'] ?? 4}');
    final area = TextEditingController(text: table?['area'] ?? 'Indoor');
    String exp = table?['experience'] ?? 'Restaurant', error = '';
    bool active = table == null || table['active'] == 1, saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(table == null ? 'Add a table' : 'Edit ${table['name']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: id,
                    enabled: table == null,
                    decoration: const InputDecoration(
                      labelText: 'Unique table ID',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Table name'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: seats,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Seats'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: exp,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Experience'),
                    items: ['Café', 'Restaurant', 'Pub & Lounge']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => update(() => exp = v!),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: area,
                    decoration: const InputDecoration(
                      labelText: 'Seating area',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => update(() => active = v),
                  ),
                  if (error.isNotEmpty)
                    Text(error, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        await Api.request(
                          '/admin/tables',
                          method: table == null ? 'POST' : 'PATCH',
                          data: {
                            'id': id.text.trim(),
                            'name': name.text.trim(),
                            'seats': int.tryParse(seats.text) ?? 0,
                            'experience': exp,
                            'area': area.text.trim(),
                            'active': active,
                          },
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        update(() {
                          error = e.toString();
                          saving = false;
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save table'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) await load();
  }

  Future<void> download(dynamic table) async {
    try {
      final painter = QrPainter(
        data: link(table),
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1000, 1200),
        Paint()..color = Colors.white,
      );
      final heading = TextPainter(
        text: const TextSpan(
          text: 'AFTER WORK',
          style: TextStyle(
            color: Color(0xFF142D29),
            fontSize: 44,
            letterSpacing: 5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900);
      heading.paint(canvas, Offset((1000 - heading.width) / 2, 60));
      canvas.save();
      canvas.translate(100, 160);
      painter.paint(canvas, const Size(800, 800));
      canvas.restore();
      final name = TextPainter(
        text: TextSpan(
          text: table['name'],
          style: const TextStyle(
            color: Color(0xFF142D29),
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900);
      name.paint(canvas, Offset((1000 - name.width) / 2, 1000));
      final caption = TextPainter(
        text: const TextSpan(
          text: 'SCAN TO EXPLORE THE MENU',
          style: TextStyle(
            color: Color(0xFF684A37),
            fontSize: 24,
            letterSpacing: 3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900);
      caption.paint(canvas, Offset((1000 - caption.width) / 2, 1090));
      final image = await recorder.endRecording().toImage(1000, 1200);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null ||
          !downloadBytes(
            bytes.buffer.asUint8List(),
            'after-work-${table['id']}-qr.png',
          )) {
        throw Exception('PNG download is supported in the web version.');
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EVERY TABLE HAS ITS OWN INVITATION',
          style: TextStyle(
            color: Color(0xFFB65C32),
            fontSize: 10,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Your tables. Their own QR.',
          style: TextStyle(
            fontFamily: 'SocialSerif',
            fontSize: 52,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Five tables to start. A separate, permanent QR link for each table. Add more whenever your space grows.',
        ),
        const SizedBox(height: 25),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFFEAE5D8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WEBSITE ADDRESS',
                style: TextStyle(fontSize: 10, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: website,
                readOnly: !manager,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'https://your-restaurant.com or http://your-computer-IP:8080',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use an address guests can open on their phones. localhost and 127.0.0.1 work only on this computer. For Wi-Fi testing, phones must use the same network.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  if (manager)
                    FilledButton(
                      onPressed: busy ? null : saveUrl,
                      child: const Text('SAVE WEBSITE ADDRESS'),
                    ),
                  OutlinedButton(
                    onPressed: load,
                    child: const Text('REFRESH TABLES'),
                  ),
                  if (manager)
                    FilledButton(
                      onPressed: () => edit(),
                      child: const Text('+ ADD TABLE'),
                    ),
                ],
              ),
              if (!manager)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'Sign in with a manager account through Account to add or edit tables and set the website address.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        if (tables == null && message.isEmpty) const LinearProgressIndicator(),
        if (tables != null)
          LayoutBuilder(
            builder: (_, c) {
              final columns = c.maxWidth < 650
                  ? 1
                  : c.maxWidth < 1000
                  ? 2
                  : 3;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: tables!
                    .map(
                      (table) => SizedBox(
                        width: (c.maxWidth - (columns - 1) * 20) / columns,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE0DAD0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      table['name'],
                                      style: const TextStyle(
                                        fontFamily: 'SocialSerif',
                                        fontSize: 32,
                                      ),
                                    ),
                                  ),
                                  if (manager)
                                    IconButton(
                                      tooltip: 'Edit ${table['name']}',
                                      onPressed: () => edit(table),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                '${table['experience']} · ${table['seats']} seats · ${table['area']}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 15),
                              if (table['active'] != 1)
                                const Padding(
                                  padding: EdgeInsets.all(50),
                                  child: Text('Inactive table'),
                                )
                              else if (website.text.trim().isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(45),
                                  child: Text(
                                    'Set the website address\nto generate this QR code.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              else ...[
                                QrImageView(
                                  data: link(table),
                                  version: QrVersions.auto,
                                  size: 210,
                                  backgroundColor: Colors.white,
                                  semanticsLabel:
                                      'Menu QR code for ${table['name']}',
                                ),
                                const Text(
                                  'SCAN TO EXPLORE THE MENU',
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                SelectableText(
                                  link(table),
                                  style: const TextStyle(fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => download(table),
                                      icon: const Icon(
                                        Icons.download,
                                        size: 15,
                                      ),
                                      label: const Text('PNG'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: link(table)),
                                        );
                                        if (mounted) {
                                          setState(
                                            () => message =
                                                '${table['name']} link copied.',
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.copy, size: 15),
                                      label: const Text('Copy link'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Semantics(liveRegion: true, child: SelectableText(message)),
          ),
        const SizedBox(height: 50),
      ],
    ),
  );
}

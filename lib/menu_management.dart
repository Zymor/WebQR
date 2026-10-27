import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'photo_picker.dart' if (dart.library.js_interop) 'photo_picker_web.dart';

typedef MenuRequest = Future<dynamic> Function(
  String path, {
  String method,
  Map<String, dynamic>? data,
});

class MenuManagement extends StatefulWidget {
  final MenuRequest request;
  final Future<Map<String, dynamic>?> Function() photoPicker;
  final String apiBase;
  final bool canManage;
  final VoidCallback? onChanged;
  const MenuManagement({
    super.key,
    required this.request,
    required this.apiBase,
    required this.canManage,
    this.onChanged,
    this.photoPicker = pickPhoto,
  });
  @override
  State<MenuManagement> createState() => _MenuManagementState();
}

class _MenuManagementState extends State<MenuManagement> {
  List<dynamic> items = [], categories = [];
  bool loading = true;
  String message = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.request('/staff/menu');
      if (mounted) {
        setState(() {
          items = data['items'];
          categories = data['categories'];
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = '$e';
          loading = false;
        });
      }
    }
  }

  String imageUrl(String path) => Uri.parse(widget.apiBase).isAbsolute
      ? Uri.parse(widget.apiBase).resolve(path).toString()
      : path;
  Widget photo(String image, {double width = 72, double height = 60}) {
    Widget fallback(BuildContext c, Object e, StackTrace? st) =>
        const Icon(Icons.restaurant, size: 35);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image.startsWith('/api/media/')
          ? Image.network(
              imageUrl(image),
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: fallback,
            )
          : image.isEmpty
          ? SizedBox(
              width: width,
              height: height,
              child: const Icon(Icons.add_photo_alternate_outlined),
            )
          : Image.asset(
              'assets/images/$image.jpg',
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: fallback,
            ),
    );
  }

  Future<void> archive(dynamic item) async {
    final archived = item['archived'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${archived ? 'Restore' : 'Remove'} ${item['name']}?'),
        content: Text(
          archived ? 'This dish will return to the customer menu.' : 'This dish will be hidden from the menu. Previous orders will be kept, and you can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(archived ? 'Restore' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final v = await widget.request(
        '/staff/menu/${item['id']}/archive',
        method: 'PATCH',
        data: {'archived': !archived},
      );
      if (mounted) setState(() => message = v['message']);
      await load();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> edit([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: item?['name'] ?? '');
    final price = TextEditingController(
      text: item == null
          ? ''
          : ((item['price'] as num) / 100).toStringAsFixed(2),
    );
    final description = TextEditingController(text: item?['description'] ?? '');
    final ingredients = TextEditingController(text: item?['ingredients'] ?? '');
    final allergens = TextEditingController(text: item?['allergens'] ?? '');
    String? category = item?['category_id'];
    String image = item?['image'] ?? '', error = '';
    bool vegetarian = item?['vegetarian'] == true,
        available = item?['available'] ?? true,
        saving = false;
    Uint8List? bytes;
    String? mime;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          Widget field(
            String label,
            TextEditingController ctrl, {
            bool required = false,
            int lines = 1,
            int max = 2000,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: ctrl,
              maxLines: lines,
              maxLength: max,
              enabled: !saving,
              decoration: InputDecoration(labelText: label),
              validator: (v) => required && (v == null || v.trim().isEmpty)
                  ? 'Please enter $label'
                  : null,
            ),
          );
          return AlertDialog(
            title: Text(item == null ? 'Add dish' : 'Edit dish'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: bytes != null
                            ? Image.memory(
                                bytes!,
                                height: 160,
                                fit: BoxFit.contain,
                              )
                            : photo(image, width: 250, height: 160),
                      ),
                      Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            image.isEmpty && bytes == null
                                ? 'Upload photo'
                                : 'Replace photo',
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  try {
                                    final picked = await widget.photoPicker();
                                    if (picked != null && c.mounted) {
                                      update(() {
                                        bytes = picked['bytes'];
                                        mime = picked['mime'];
                                        error = '';
                                      });
                                    }
                                  } catch (e) {
                                    if (c.mounted) update(() => error = '$e');
                                  }
                                },
                        ),
                      ),
                      const Text(
                        'JPEG, PNG or WebP · up to 2 MB',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      field('Dish name', name, required: true, max: 150),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: categories
                            .map(
                              (v) => DropdownMenuItem<String>(
                                value: v['id'],
                                child: Text(
                                  '${v['name']} · ${v['experience']}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving ? null : (v) => category = v,
                        validator: (v) =>
                            v == null ? 'Choose a category' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: price,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price in USD',
                          prefixText: '\$',
                        ),
                        validator: (v) =>
                            v == null ||
                                !RegExp(r'^\d{1,5}(\.\d{1,2})?$')
                                    .hasMatch(v.trim()) ||
                                (double.tryParse(v) ?? -1) > 10000
                            ? 'Enter a price from 0 to 10000 with up to 2 decimals'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      field(
                        'Description',
                        description,
                        required: true,
                        lines: 3,
                      ),
                      field('Ingredients', ingredients, lines: 2),
                      field('Allergens', allergens, max: 300),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vegetarian'),
                        value: vegetarian,
                        onChanged: saving
                            ? null
                            : (v) => update(() => vegetarian = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(available ? 'Available' : 'Sold out'),
                        value: available,
                        onChanged: saving
                            ? null
                            : (v) => update(() => available = v),
                      ),
                      if (error.isNotEmpty)
                        Text(error, style: const TextStyle(color: Colors.red)),
                      if (saving) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        if (image.isEmpty && bytes == null) {
                          update(() => error = 'Please upload a dish photo.');
                          return;
                        }
                        update(() {
                          saving = true;
                          error = '';
                        });
                        try {
                          if (bytes != null) {
                            final upload = await widget.request(
                              '/staff/media',
                              method: 'POST',
                              data: {
                                'mime': mime,
                                'base64': base64Encode(bytes!),
                              },
                            );
                            image = upload['image'];
                            bytes = null;
                          }
                          await widget.request(
                            '/staff/menu',
                            method: item == null ? 'POST' : 'PATCH',
                            data: {
                              'id': item?['id'],
                              'name': name.text.trim(),
                              'category_id': category,
                              'price': (double.parse(price.text.trim()) * 100)
                                  .round(),
                              'description': description.text.trim(),
                              'ingredients': ingredients.text.trim(),
                              'allergens': allergens.text.trim(),
                              'image': image,
                              'vegetarian': vegetarian,
                              'available': available,
                            },
                          );
                          if (c.mounted) Navigator.pop(c, true);
                        } catch (e) {
                          if (c.mounted) {
                            update(() {
                              saving = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save dish'),
              ),
            ],
          );
        },
      ),
    );
    // Dispose after the dialog's reverse animation no longer uses the fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final ctrl in [name, price, description, ingredients, allergens]) {
      ctrl.dispose();
    }
    if (saved == true) {
      if (mounted) setState(() => message = 'Dish saved.');
      await load();
      widget.onChanged?.call();
    }
  }

  Widget actions(dynamic item) => Wrap(
    spacing: 4,
    children: [
      if (widget.canManage) ...[
        IconButton(
          tooltip: 'Edit ${item['name']}',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => edit(Map<String, dynamic>.from(item)),
        ),
        IconButton(
          tooltip:
              '${item['archived'] == true ? 'Restore' : 'Remove'} ${item['name']}',
          icon: Icon(
            item['archived'] == true ? Icons.restore : Icons.delete_outline,
          ),
          onPressed: () => archive(item),
        ),
      ],
    ],
  );
  String availability(dynamic item) => item['archived'] == true
      ? 'Archived'
      : item['available'] == true
      ? 'Available'
      : 'Sold out';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (widget.canManage)
            FilledButton.icon(
              onPressed: loading ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add dish'),
            ),
          OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh menu'),
          ),
        ],
      ),
      if (message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(liveRegion: true, child: Text(message)),
        ),
      const SizedBox(height: 16),
      if (loading)
        const LinearProgressIndicator()
      else
        LayoutBuilder(
          builder: (c, size) => size.maxWidth < 750
              ? Column(
                  children: items
                      .map(
                        (m) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                photo(
                                  m['image'],
                                  width: double.infinity,
                                  height: 160,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  m['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  '${m['category']} · \$${((m['price'] as num) / 100).toStringAsFixed(2)}',
                                ),
                                Row(
                                  children: [
                                    Expanded(child: Text(availability(m))),
                                    actions(m),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    columns: const [
                      DataColumn(label: Text('Photo')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Price')),
                      DataColumn(label: Text('Availability')),
                      DataColumn(label: Text('Actions')),
                    ],
                    dataRowMinHeight: 80,
                    dataRowMaxHeight: 100,
                    rows: items
                        .map(
                          (m) => DataRow(
                            cells: [
                              DataCell(photo(m['image'])),
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 200,
                                  ),
                                  child: Text(m['name']),
                                ),
                              ),
                              DataCell(Text(m['category'])),
                              DataCell(
                                Text(
                                  '\$${((m['price'] as num) / 100).toStringAsFixed(2)}',
                                ),
                              ),
                              DataCell(Text(availability(m))),
                              DataCell(actions(m)),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
    ],
  );
}

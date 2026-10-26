import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'service_pages.dart';
import 'local_store.dart' if (dart.library.js_interop) 'local_store_web.dart';

class OrderCheckout extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onOrdered;
  const OrderCheckout({
    super.key,
    required this.order,
    required this.onOrdered,
  });
  @override
  State<OrderCheckout> createState() => _OrderCheckoutState();
}

class _OrderCheckoutState extends State<OrderCheckout> {
  final name = TextEditingController(), notes = TextEditingController();
  Map<String, dynamic>? quote, order;
  String? orderId, accessToken, requestKey;
  String message = '';
  bool busy = false, loaded = false;
  Timer? poll;
  void saveDraft() => writeLocal(
    'afterwork.checkout_draft',
    jsonEncode({'name': name.text, 'notes': notes.text}),
  );
  String secureToken() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  String money(dynamic n) => '\$${((n as num) / 100).toStringAsFixed(2)}';
  @override
  void initState() {
    super.initState();
    try {
      final draft = readLocal('afterwork.checkout_draft');
      if (draft != null) {
        final v = jsonDecode(draft);
        name.text = v['name'] ?? '';
        notes.text = v['notes'] ?? '';
      }
    } catch (_) {}
    try {
      final last = readLocal('afterwork.last_order');
      if (last != null) {
        final v = jsonDecode(last);
        orderId = v['id'];
        accessToken = v['token'];
        if ((widget.order['items'] as List).isEmpty) {
          refreshOrder();
          startPolling();
        }
      }
    } catch (_) {}
    if ((widget.order['items'] as List).isNotEmpty) {
      loadQuote();
    } else if (orderId == null) {
      loaded = true;
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> loadQuote() async {
    setState(() => busy = true);
    try {
      final v = await Api.request(
        '/orders/quote',
        method: 'POST',
        data: widget.order,
      );
      if (mounted) {
        setState(() {
          quote = Map<String, dynamic>.from(v);
          order = null;
          orderId = null;
          message = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          loaded = true;
        });
      }
    }
  }

  void startPolling() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => refreshOrder());
  }

  Future<void> refreshOrder() async {
    if (orderId == null || accessToken == null) return;
    try {
      final v = await Api.request(
        '/orders/${Uri.encodeComponent(orderId!)}',
        orderToken: accessToken,
      );
      if (mounted) {
        setState(() {
          order = Map<String, dynamic>.from(v['order']);
          message = '';
          loaded = true;
        });
      }
      if (['completed', 'cancelled', 'rejected'].contains(order?['status'])) {
        poll?.cancel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = 'Connection interrupted. Your order is saved; retrying automatically.';
          loaded = true;
        });
      }
    }
  }

  Future<void> submit() async {
    if (busy || quote == null || order != null) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final data = <String, dynamic>{
        ...widget.order,
        'items': (quote!['items'] as List)
            .map(
              (i) => {
                'id': i['id'],
                'quantity': i['quantity'],
                'unit_price': i['unit_price'],
                'notes': i['notes'],
              },
            )
            .toList(),
        'name': name.text,
        'notes': notes.text,
      };
      final fingerprint = jsonEncode(data);
      Map<String, dynamic>? pending;
      try {
        final raw = readLocal('afterwork.pending_order');
        if (raw != null) {
          final v = Map<String, dynamic>.from(jsonDecode(raw));
          if (v['fingerprint'] == fingerprint) pending = v;
        }
      } catch (_) {}
      requestKey = pending?['key'] ?? secureToken();
      accessToken = pending?['token'] ?? secureToken();
      writeLocal(
        'afterwork.pending_order',
        jsonEncode({
          'key': requestKey,
          'token': accessToken,
          'fingerprint': fingerprint,
        }),
      );
      final v = await Api.request(
        '/orders',
        method: 'POST',
        data: {...data, 'request_key': requestKey, 'access_token': accessToken},
      );
      orderId = v['order']['id'];
      writeLocal(
        'afterwork.last_order',
        jsonEncode({'id': orderId, 'token': accessToken}),
      );
      writeLocal('afterwork.pending_order', '');
      if (mounted) {
        setState(() => order = Map<String, dynamic>.from(v['order']));
      }
      widget.onOrdered();
      startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget summary(Map<String, dynamic> data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        data['table_name'] ?? data['table']?['name'] ?? 'Your table',
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 20),
      ...(data['items'] as List).map(
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  '${i['quantity']}×',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i['name']),
                    if ((i['notes'] ?? '').isNotEmpty)
                      Text(
                        i['notes'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                  ],
                ),
              ),
              Text(money(i['unit_price'] * i['quantity'])),
            ],
          ),
        ),
      ),
      const Divider(height: 35),
      line('Subtotal', money(data['subtotal'])),
      line('Tax', money(data['tax'])),
      line('Total · USD', money(data['total']), bold: true),
      const SizedBox(height: 12),
      const Text(
        'Pay at the counter · Payment not yet collected',
        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
    ],
  );
  Widget line(String left, String right, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            left,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          right,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order != null
                  ? 'Your order is with us.'
                  : 'A little something for your table.',
              style: const TextStyle(
                fontFamily: 'SocialSerif',
                fontSize: 45,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 25),
            if (busy || !loaded) const LinearProgressIndicator(),
            if (order != null) ...[
              SelectableText(
                order!['id'],
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EDFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'Status: ${order!['status'].toString().toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A38A8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              summary(order!),
              const SizedBox(height: 20),
              const Text(
                'Your order has been saved. Staff will review it before preparation. This screen updates automatically.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              if ((order!['history'] as List).isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Order progress'),
                  children: (order!['history'] as List)
                      .map(
                        (h) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(h['status']),
                          subtitle: Text(
                            h['reason'].toString().isEmpty
                                ? h['created_at']
                                : h['reason'],
                          ),
                        ),
                      )
                      .toList(),
                ),
              TextButton.icon(
                onPressed: refreshOrder,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh order status'),
              ),
            ] else if (quote != null) ...[
              summary(quote!),
              const SizedBox(height: 30),
              TextField(
                controller: name,
                onChanged: (_) => saveDraft(),
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: notes,
                onChanged: (_) => saveDraft(),
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Order notes (optional)',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'SENDING…'
                        : 'PLACE ORDER · ${money(quote!['total'])}',
                  ),
                ),
              ),
            ] else if (loaded) ...[
              const Text('Scan your table QR code and add dishes to begin.'),
              if ((widget.order['items'] as List).isNotEmpty)
                TextButton(
                  onPressed: loadQuote,
                  child: const Text('Check table and prices again'),
                ),
            ],
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: const TextStyle(color: Color(0xFF9A4828)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

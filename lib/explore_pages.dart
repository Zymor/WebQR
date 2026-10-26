import 'package:flutter/material.dart';

import 'service_pages.dart';

class ExplorePage extends StatefulWidget {
  final String page;
  const ExplorePage({super.key, required this.page});
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  List<dynamic>? events;
  Map<String, dynamic>? settings;
  String filter = 'All', error = '';
  bool busy = false, consent = false;
  final email = TextEditingController(),
      name = TextEditingController(),
      token = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    email.dispose();
    name.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final response = await Api.request(
        widget.page == 'Events' ? '/events' : '/settings',
      );
      if (mounted) {
        setState(() {
          if (widget.page == 'Events') {
            events = response['events'];
          } else {
            settings = Map<String, dynamic>.from(response);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget heading(String s) => Text(
    s,
    style: const TextStyle(
      fontFamily: 'SocialSerif',
      fontSize: 48,
      height: 1.1,
    ),
  );
  Future<void> subscribe() async {
    setState(() => busy = true);
    try {
      final response = await Api.request(
        '/newsletter',
        method: 'POST',
        data: {'email': email.text, 'consent': consent},
      );
      if (mounted) {
        setState(
          () => error =
              '${response['message']}\nUnsubscribe token: ${response['unsubscribe_token']}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget gallery() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('A taste of life here.'),
      const SizedBox(height: 20),
      const Text(
        'A collection of inspiration for our café, kitchen and evenings together.',
      ),
      const SizedBox(height: 25),
      Wrap(
        spacing: 10,
        children: ['All', 'Café', 'Restaurant']
            .map(
              (s) => ChoiceChip(
                label: Text(s),
                selected: filter == s,
                onSelected: (_) => setState(() => filter = s),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 25),
      LayoutBuilder(
        builder: (_, c) {
          final columns = c.maxWidth < 600 ? 1 : 3;
          final photos = [
            ('coffee', 'Café'),
            ('dessert', 'Café'),
            ('sandwich', 'Café'),
            ('chicken', 'Restaurant'),
            ('sushi', 'Restaurant'),
            ('restaurant', 'Restaurant'),
          ].where((p) => filter == 'All' || p.$2 == filter);
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: photos
                .map(
                  (p) => SizedBox(
                    width: (c.maxWidth - (columns - 1) * 16) / columns,
                    child: InkWell(
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          child: Stack(
                            children: [
                              Image.asset(
                                'assets/images/${p.$1}.jpg',
                                fit: BoxFit.contain,
                              ),
                              Positioned(
                                right: 10,
                                top: 10,
                                child: IconButton.filled(
                                  tooltip: 'Close image',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/images/${p.$1}.jpg',
                          height: 300,
                          fit: BoxFit.cover,
                          semanticLabel: '${p.$2} ${p.$1} inspiration',
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
  Future<void> register(dynamic event) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event['title']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(event['description']),
            const SizedBox(height: 15),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Register for demo event'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      final response = await Api.request(
        '/events/register',
        method: 'POST',
        data: {'event_id': event['id'], 'name': name.text, 'email': email.text},
      );
      if (mounted) {
        setState(
          () => error = '${response['message']} Reference: ${response['id']}',
        );
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget eventList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Make a moment of it.'),
      const SizedBox(height: 20),
      const Text(
        'Acoustic evenings, coffee workshops, and memorable meals. Demonstration events are managed by the local administrator.',
      ),
      const SizedBox(height: 25),
      if (events == null && error.isEmpty) const LinearProgressIndicator(),
      if (events != null && events!.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('Our calendar is taking shape. No published events yet.'),
        ),
      if (events != null)
        ...events!.map(
          (e) => Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e['date']} · ${e['time']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e['title'],
                    style: const TextStyle(
                      fontFamily: 'SocialSerif',
                      fontSize: 32,
                    ),
                  ),
                  Text(e['description']),
                  const SizedBox(height: 15),
                  Text('${e['registered']} / ${e['capacity']} places booked'),
                  const SizedBox(height: 15),
                  if (e['status'] == 'cancelled')
                    const Text('Cancelled')
                  else if (e['registered'] >= e['capacity'])
                    const Text('Sold out')
                  else
                    FilledButton(
                      onPressed: () => register(e),
                      child: const Text('VIEW & REGISTER'),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
  Widget contact() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('There’s a place for you here.'),
      const SizedBox(height: 25),
      if (settings == null && error.isEmpty) const LinearProgressIndicator(),
      if (settings != null) ...[
        Text(
          (settings!['address'] as String).isEmpty
              ? 'Location to be announced'
              : settings!['address'],
        ),
        Text(
          (settings!['phone'] as String).isEmpty
              ? 'Phone to be announced'
              : settings!['phone'],
        ),
        Text(
          (settings!['email'] as String).isEmpty
              ? 'Email to be announced'
              : settings!['email'],
        ),
        const SizedBox(height: 25),
        const Text(
          'Opening hours · Asia/Phnom_Penh',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        ...(settings!['hours'] as Map).entries.map(
          (e) => Text('${e.key}: ${e.value[0]}:00 – ${e.value[1]}:00'),
        ),
        const SizedBox(height: 25),
        const Text(
          'Official location, parking and social links will appear when supplied by the venue.',
        ),
      ],
    ],
  );
  Widget newsletter() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Stay in good company.'),
      const SizedBox(height: 20),
      const Text(
        'Email delivery is not configured. This form records consent in the local demonstration database.',
      ),
      const SizedBox(height: 25),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: consent,
        onChanged: (b) => setState(() => consent = b!),
        title: const Text(
          'I agree to receive news from After Work.',
          style: TextStyle(fontSize: 13),
        ),
      ),
      FilledButton(
        onPressed: busy ? null : subscribe,
        child: const Text('SAVE SUBSCRIPTION CONSENT'),
      ),
      const SizedBox(height: 35),
      TextField(
        controller: token,
        decoration: const InputDecoration(labelText: 'Unsubscribe token'),
      ),
      const SizedBox(height: 15),
      OutlinedButton(
        onPressed: () async {
          try {
            final value = await Api.request(
              '/newsletter/unsubscribe',
              method: 'POST',
              data: {'token': token.text},
            );
            if (mounted) setState(() => error = value['message']);
          } catch (e) {
            if (mounted) setState(() => error = e.toString());
          }
        },
        child: const Text('Unsubscribe'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (widget.page) {
          'Gallery' => gallery(),
          'Events' => eventList(),
          'Contact' => contact(),
          _ => newsletter(),
        },
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Semantics(liveRegion: true, child: SelectableText(error)),
          ),
        if (error.isNotEmpty && widget.page != 'Newsletter')
          TextButton(
            onPressed: () {
              setState(() => error = '');
              load();
            },
            child: const Text('Refresh'),
          ),
        const SizedBox(height: 60),
      ],
    ),
  );
}

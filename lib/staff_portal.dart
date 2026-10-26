import 'package:flutter/material.dart';

import 'service_pages.dart';
import 'local_store.dart' if (dart.library.js_interop) 'local_store_web.dart';

class StaffPortal extends StatelessWidget {
  const StaffPortal({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AFTER WORK / STAFF',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Color(0xFF0A38A8),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Behind the good moments.',
          style: TextStyle(fontFamily: 'SocialSerif', fontSize: 48),
        ),
        const SizedBox(height: 20),
        const Text(
          'Orders, kitchen preparation and table management are in the protected staff website.',
        ),
        const SizedBox(height: 25),
        FilledButton(
          onPressed: () async {
            String url = 'https://afterwork-admin.vercel.app';
            try {
              final config = await Api.request('/settings');
              if ((config['staff_url'] ?? '').toString().isNotEmpty) {
                url = config['staff_url'];
              }
            } catch (_) {}
            if (!openWebsite(url) && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: SelectableText(url)));
            }
          },
          child: const Text('OPEN STAFF WEBSITE ↗'),
        ),
      ],
    ),
  );
}

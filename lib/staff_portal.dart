import 'package:flutter/material.dart';

import 'service_pages.dart';
import 'menu_management.dart';
import 'local_store.dart' if (dart.library.js_interop) 'local_store_web.dart';

class StaffPortal extends StatefulWidget {
  final VoidCallback? onMenuChanged;
  const StaffPortal({super.key, this.onMenuChanged});
  @override
  State<StaffPortal> createState() => _StaffPortalState();
}

class _StaffPortalState extends State<StaffPortal> {
  final email = TextEditingController(), password = TextEditingController();
  Map<String, dynamic>? user;
  bool busy = false, managing = false;
  String message = '';
  @override
  void initState() {
    super.initState();
    if (Api.token != null) restore();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> restore() async {
    setState(() => busy = true);
    try {
      final v = await Api.request('/staff/me');
      if (mounted) {
        setState(() {
          user = Map<String, dynamic>.from(v['user']);
          Api.user = user;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final v = await Api.request(
        '/staff/auth/login',
        method: 'POST',
        data: {'email': email.text.trim(), 'password': password.text},
      );
      Api.remember(v['token']);
      Api.user = Map<String, dynamic>.from(v['user']);
      password.clear();
      if (mounted) setState(() => user = Api.user);
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    setState(() => busy = true);
    try {
      await Api.request('/staff/auth/logout', method: 'POST');
    } catch (_) {
    } finally {
      Api.remember(null);
      Api.user = null;
      if (mounted) {
        setState(() {
          user = null;
          managing = false;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AFTER WORK / ADMIN',
          style: TextStyle(
            color: Color(0xFF0A38A8),
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          managing ? 'Manage menu' : 'Staff sign in',
          style: const TextStyle(fontFamily: 'SocialSerif', fontSize: 42),
        ),
        const SizedBox(height: 20),
        if (busy) const LinearProgressIndicator(),
        if (user == null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                const Text(
                  'Use the same admin account as the staff website. Guests can order without signing in.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Admin email'),
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) {
                    if (!busy) login();
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: const Text('Sign in'),
                ),
              ],
            ),
          )
        else ...[
          Text('Signed in as ${user!['name']} · ${user!['role']}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (['owner', 'manager'].contains(user!['role']))
                FilledButton.icon(
                  onPressed: () => setState(() => managing = !managing),
                  icon: const Icon(Icons.restaurant_menu),
                  label: Text(managing ? 'Back to account' : 'Manage menu'),
                ),
              OutlinedButton(
                onPressed: () =>
                    openWebsite('https://afterwork-admin.vercel.app'),
                child: const Text('Open staff dashboard ↗'),
              ),
              TextButton(
                onPressed: busy ? null : logout,
                child: const Text('Sign out'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (managing && ['owner', 'manager'].contains(user!['role']))
            MenuManagement(
              request: Api.request,
              apiBase: Api.base,
              canManage: true,
              onChanged: widget.onMenuChanged,
            ),
        ],
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Semantics(liveRegion: true, child: Text(message)),
          ),
      ],
    ),
  );
}

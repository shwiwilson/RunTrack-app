import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/form_page.dart';
import '../auth/auth_page.dart';
import 'download_export.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _busy = false;
  bool _isError = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.client
          .from('profiles')
          .select('display_name')
          .eq('id', widget.client.auth.currentUser!.id)
          .single();
      if (mounted) _name.text = profile['display_name'] as String;
    } catch (error) {
      _notice = accountError(error);
      _isError = true;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _act(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final message = await action();
      if (mounted) {
        setState(() {
          _notice = message;
          _isError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = error is FunctionException
              ? 'The account service could not complete the request. Check your '
                    'password and connection, or ask the website owner to check deployment.'
              : accountError(error);
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your RunTrack account?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently deletes your profile, running history, '
                'memberships and provider credentials. Club sessions you created '
                'remain without your identity. Export your data first if you want a copy. '
                'If you are the only club administrator, appoint another administrator first.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          TextButton(
            onPressed: () {
              if (confirm.text == 'DELETE' && password.text.isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    final secret = password.text;
    password.clear();
    // Dialog text fields complete their exit animation before disposal.
    Future<void>.delayed(const Duration(seconds: 1), () {
      password.dispose();
      confirm.dispose();
    });
    if (accepted != true || !mounted) return;
    await _act(() async {
      await widget.client.functions.invoke(
        'delete-account',
        body: {'password': secret, 'confirmation': 'DELETE'},
      );
      await widget.client.auth.signOut(scope: SignOutScope.local);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return 'Account deleted.';
    });
  }

  @override
  Widget build(BuildContext context) => FormPage(
    showBack: true,
    title: 'Your account.',
    subtitle:
        widget.client.auth.currentUser?.email ??
        'Manage your RunTrack account.',
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_notice != null) FormNotice(_notice!, error: _isError),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  maxLength: 100,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (_form.currentState!.validate()) {
                            _act(() async {
                              await widget.client
                                  .from('profiles')
                                  .update({'display_name': _name.text.trim()})
                                  .eq('id', widget.client.auth.currentUser!.id)
                                  .select('id')
                                  .single();
                              return 'Profile saved.';
                            });
                          }
                        },
                  child: const Text('Save profile'),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<ThemeMode>(
                  initialValue: ThemeController.instance.themeMode,
                  decoration: const InputDecoration(labelText: 'Appearance'),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Use device setting'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                  onChanged: ThemeController.instance.updateThemeMode,
                ),
                const SizedBox(height: 24),
                Text(
                  'Privacy and your data',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your activities start private. Club administrators cannot view '
                  'private workouts or heart-rate measurements. You can choose to share '
                  'a summary of a run with your club from the activity feed. '
                  'Google Health access is read-only and optional. Disconnect it from '
                  'Connect your running data; this keeps previously imported workouts '
                  'until you delete your account.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          final response = await widget.client.functions.invoke(
                            'export-data',
                          );
                          return downloadExport(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(response.data),
                          );
                        }),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export my data'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          await widget.client.auth.resetPasswordForEmail(
                            widget.client.auth.currentUser!.email!,
                            redirectTo: authRedirect(recovery: true),
                          );
                          return 'Password reset email requested. Open it in this browser.';
                        }),
                  child: const Text('Change password by email'),
                ),
                const Divider(height: 40),
                TextButton(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Delete my account'),
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
  );
}

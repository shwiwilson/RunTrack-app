import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/widgets/form_page.dart';

enum AuthMode { signIn, register, recover }

/// Redirects stay on this installation and carry no credentials in the URL.
String authRedirect({bool recovery = false}) => Uri.base
    .replace(
      path: Uri.base.path.endsWith('index.html') ? Uri.base.path : '/',
      queryParameters: recovery ? {'flow': 'recovery'} : const {},
      fragment: '',
    )
    .toString();

String accountError(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) {
    // Database functions use explicit user-safe messages for validation failures.
    if (error.code == 'P0001' || error.code == '42501') return error.message;
  }
  return 'RunTrack could not reach the service. Check your connection and try again.';
}

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.client,
    required this.bootstrapPending,
  });
  final SupabaseClient client;
  final bool bootstrapPending;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  AuthMode _mode = AuthMode.signIn;
  bool _busy = false;
  bool _obscure = true;
  bool _noticeError = false;
  String? _notice;
  String? _verificationEmail;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final email = _email.text.trim();
      switch (_mode) {
        case AuthMode.register:
          final response = await widget.client.auth.signUp(
            email: email,
            password: _password.text,
            data: {'display_name': _name.text.trim()},
            emailRedirectTo: authRedirect(),
          );
          if (!mounted) return;
          if (response.session == null) {
            setState(() {
              _verificationEmail = email;
              _notice =
                  'Check your email to verify your account, then sign in. '
                  'Open the link in this browser on this device. If you already '
                  'have an account, use Sign in or Forgot password.';
              _noticeError = false;
            });
          }
          _password.clear();
        case AuthMode.signIn:
          await widget.client.auth.signInWithPassword(
            email: email,
            password: _password.text,
          );
          _password.clear();
        case AuthMode.recover:
          await widget.client.auth.resetPasswordForEmail(
            email,
            redirectTo: authRedirect(recovery: true),
          );
          if (!mounted) return;
          setState(() {
            _notice =
                'If this email has an account, a reset link is on its way. '
                'Open it in this browser on this device.';
            _noticeError = false;
          });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = accountError(error);
          _noticeError = true;
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

  Future<void> _resend() async {
    setState(() {
      _busy = true;
    });
    try {
      await widget.client.auth.resend(
        type: OtpType.signup,
        email: _verificationEmail!,
        emailRedirectTo: authRedirect(),
      );
      if (mounted) {
        setState(() {
          _notice =
              'Verification email requested. Check your inbox and spam folder.';
          _noticeError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notice = accountError(error);
          _noticeError = true;
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

  void _changeMode(AuthMode mode) => setState(() {
    _mode = mode;
    _notice = null;
    _password.clear();
    _form.currentState?.reset();
  });

  Future<void> _openPrivacy() async {
    try {
      final opened = await launchUrl(
        Uri.base.resolve('privacy.html'),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open /privacy.html in your browser, or contact hello@tswebdev.co.uk.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final register = _mode == AuthMode.register;
    final recover = _mode == AuthMode.recover;
    return FormPage(
      title: register
          ? 'Your next chapter starts here.'
          : recover
          ? 'Find your way back.'
          : 'Your running. Your club.',
      subtitle: register
          ? 'Create your personal RunTrack account. Your training '
                'stays private until you choose to share it.'
          : recover
          ? 'We’ll send you a secure password reset link.'
          : 'A space for your training, your progress and the people you run with.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.bootstrapPending)
                const FormNotice(
                  'RunTrack is preparing to open. Registration is currently reserved '
                  'for the designated founding administrator.',
                ),
              if (_notice != null) FormNotice(_notice!, error: _noticeError),
              if (register) ...[
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  maxLength: 100,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email address'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                textInputAction: recover
                    ? TextInputAction.done
                    : TextInputAction.next,
                validator: (v) =>
                    v == null ||
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v.trim())
                    ? 'Enter a valid email address.'
                    : null,
                onFieldSubmitted: recover ? (_) => _submit() : null,
              ),
              if (!recover) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: register ? 'Use at least 12 characters.' : null,
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() {
                        _obscure = !_obscure;
                      }),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: _obscure,
                  autofillHints: [
                    register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Enter your password.'
                      : register && v.length < 12
                      ? 'Use at least 12 characters.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy
                      ? 'Please wait…'
                      : register
                      ? 'Create account'
                      : recover
                      ? 'Send reset link'
                      : 'Sign in',
                ),
              ),
              if (_verificationEmail != null)
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Resend verification email'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _changeMode(
                        _mode == AuthMode.signIn
                            ? AuthMode.register
                            : AuthMode.signIn,
                      ),
                child: Text(
                  _mode == AuthMode.signIn
                      ? 'Create account'
                      : 'Back to sign in',
                ),
              ),
              if (_mode == AuthMode.signIn)
                TextButton(
                  onPressed: _busy ? null : () => _changeMode(AuthMode.recover),
                  child: const Text('Forgot password?'),
                ),
              const SizedBox(height: 16),
              Text(
                'No location access is needed. Connecting running data is optional. '
                'You can export your data or delete your account in Account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: _openPrivacy,
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text('Privacy and your data'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.client,
    required this.onComplete,
  });
  final SupabaseClient client;
  final Future<void> Function() onComplete;
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      _password.clear();
      await widget.onComplete();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = accountError(error);
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

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Choose a new password.',
    subtitle: 'Keep your running account secure with a unique password.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) FormNotice(_error!, error: true),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least 12 characters',
            ),
            validator: (v) =>
                (v?.length ?? 0) < 12 ? 'Use at least 12 characters.' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save password'),
          ),
        ],
      ),
    ),
  );
}

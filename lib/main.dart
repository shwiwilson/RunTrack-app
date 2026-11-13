import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/platform/browser_location.dart';
import 'core/theme/run_track_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/form_page.dart';
import 'features/auth/auth_page.dart';
import 'features/account/account_page.dart';
import 'features/health/health_setup_page.dart';
import 'run_track_shell.dart';

/// A completed OAuth return belongs on the normal app shell, not back inside
/// the setup flow. Results that require the runner to act still reopen setup.
String? healthReturnLandingNotice(String? result) => switch (result) {
  'linked' =>
    'Google Health is connected. Your latest workouts have been checked.',
  'partial' =>
    'Google Health is connected. Some older workout history is still available to sync.',
  _ => null,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final recovery = Uri.base.queryParameters['flow'] == 'recovery';
  final healthReturn = Uri.base.queryParameters['health'] == 'return';
  final config = AppConfig.fromEnvironment();
  String? error = config.validationError;
  SupabaseClient? client;
  if (error == null) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
        postgrestOptions: const PostgrestClientOptions(
          requestTimeout: Duration(seconds: 15),
          retryCount: 1,
        ),
      );
      client = Supabase.instance.client;
    } catch (_) {
      error =
          'RunTrack could not start its secure session. Check your connection '
          'and the website’s Supabase configuration, then reload.';
    }
  }
  runApp(
    RunTrackApp(
      client: client,
      configurationError: error,
      recovery: recovery,
      healthReturn: healthReturn,
    ),
  );
}

class RunTrackApp extends StatelessWidget {
  const RunTrackApp({
    super.key,
    this.client,
    this.configurationError,
    this.recovery = false,
    this.healthReturn = false,
  });
  final SupabaseClient? client;
  final String? configurationError;
  final bool recovery;
  final bool healthReturn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeController.instance,
    builder: (context, _) => MaterialApp(
      title: 'RunTrack',
      debugShowCheckedModeBanner: false,
      theme: runTrackTheme(Brightness.light),
      darkTheme: runTrackTheme(Brightness.dark),
      themeMode: ThemeController.instance.themeMode,
      home: client == null
          ? SetupPage(
              message:
                  configurationError ??
                  'This RunTrack installation needs its Supabase configuration.',
            )
          : AuthGate(
              client: client!,
              recovery: recovery,
              healthReturn: healthReturn,
            ),
    ),
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({
    super.key,
    required this.message,
    this.onRetry,
    this.onSignOut,
  });
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Getting RunTrack ready.',
    subtitle: 'Your running community starts here.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.settings_outlined, size: 36),
        const SizedBox(height: 16),
        FormNotice(message, error: true),
        if (onRetry != null)
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: const Text('Sign out')),
      ],
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.client,
    this.recovery = false,
    this.healthReturn = false,
  });
  final SupabaseClient client;
  final bool recovery;
  final bool healthReturn;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  bool _loading = true;
  bool _bootstrapPending = true;
  bool _setupRequired = false;
  bool _recovery = false;
  bool _showClubPrompt = false;
  String? _error;
  String? _healthNotice;
  String? _loadedUser;
  int _loadGeneration = 0;
  bool _healthReturnHandled = false;

  @override
  void initState() {
    super.initState();
    _recovery = widget.recovery;
    _subscription = widget.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _recovery = true;
            _loading = false;
          });
        } else if (state.event == AuthChangeEvent.signedOut) {
          _loadedUser = null;
          _recovery = false;
          scheduleMicrotask(() {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
          scheduleMicrotask(_load);
        } else if (state.session?.user.id != _loadedUser && !_recovery) {
          // Never await Supabase operations inside its auth stream callback.
          scheduleMicrotask(_load);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _error = accountError(error);
            _loading = false;
          });
        }
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bootstrap = Map<String, dynamic>.from(
        await widget.client.rpc('bootstrap_status') as Map,
      );
      final user = widget.client.auth.currentUser;
      bool showClub = false;
      if (user != null && user.emailConfirmedAt != null && !_recovery) {
        final profile = Map<String, dynamic>.from(
          await widget.client.rpc('ensure_profile') as Map,
        );
        final membership = await widget.client
            .from('club_memberships')
            .select('id')
            .eq('user_id', user.id)
            .eq('status', 'active')
            .limit(1);
        final onboarding = profile['onboarding'] as Map? ?? {};
        showClub =
            membership.isEmpty && onboarding['club_prompt_dismissed'] != true;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bootstrapPending = bootstrap['bootstrap_pending'] != false;
        _setupRequired = bootstrap['setup_required'] != false;
        _showClubPrompt = showClub;
        _loadedUser = user?.id;
      });
      if (user != null &&
          user.emailConfirmedAt != null &&
          widget.healthReturn &&
          !_healthReturnHandled) {
        _healthReturnHandled = true;
        final notice = healthReturnLandingNotice(
          Uri.base.queryParameters['health_result'],
        );
        if (notice != null) {
          setState(() => _healthNotice = notice);
          clearAccountIntent();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openHealth());
          });
        }
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = accountError(error);
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.client.auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(accountError(error))));
      }
    }
  }

  Future<void> _openHealth() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HealthSetupPage(client: widget.client),
      ),
    );
    clearAccountIntent();
    if (mounted && widget.client.auth.currentUser != null) await _load();
  }

  Future<void> _openClub() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => ClubJoinPage(
          client: widget.client,
          showBack: true,
          onComplete: () async {
            if (routeContext.mounted) Navigator.pop(routeContext);
          },
          onSkip: () async {
            if (routeContext.mounted) Navigator.pop(routeContext);
          },
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _setupRequired) {
      return SetupPage(
        message:
            _error ??
            'The founding administrator configuration is missing. '
                'The website owner must finish the protected bootstrap setup before registration opens.',
        onRetry: () => unawaited(_load()),
        onSignOut: widget.client.auth.currentUser == null
            ? null
            : () => unawaited(_signOut()),
      );
    }
    final user = widget.client.auth.currentUser;
    if (user == null) {
      return AuthPage(
        client: widget.client,
        bootstrapPending: _bootstrapPending,
      );
    }
    if (_recovery) {
      return PasswordResetPage(
        client: widget.client,
        onComplete: () async {
          _recovery = false;
          clearAccountIntent();
          await _signOut();
          await _load();
        },
      );
    }
    if (user.emailConfirmedAt == null) {
      return FormPage(
        title: 'Verify your email.',
        subtitle: 'Confirm your address before entering RunTrack.',
        child: Column(
          children: [
            const Text(
              'Open the verification link from your inbox in this browser.',
            ),
            TextButton(
              onPressed: () => unawaited(_signOut()),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      );
    }
    if (_showClubPrompt) {
      return ClubJoinPage(
        client: widget.client,
        onComplete: () async {
          await _load();
          if (mounted) await _openHealth();
        },
        onSkip: () async {
          await widget.client.rpc(
            'update_onboarding',
            params: {
              'p_patch': {'club_prompt_dismissed': true},
            },
          );
          await _load();
        },
      );
    }
    return RunTrackShell(
      key: ValueKey(user.id),
      client: widget.client,
      healthNotice: _healthNotice,
      onDismissHealthNotice: () => setState(() => _healthNotice = null),
      onConnectHealth: () => unawaited(_openHealth()),
      onJoinClub: () => unawaited(_openClub()),
      onAccount: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountPage(client: widget.client),
          ),
        );
        if (mounted && widget.client.auth.currentUser != null) await _load();
      },
      onSignOut: _signOut,
    );
  }
}

class ClubJoinPage extends StatefulWidget {
  const ClubJoinPage({
    super.key,
    required this.client,
    required this.onComplete,
    required this.onSkip,
    this.showBack = false,
  });
  final SupabaseClient client;
  final Future<void> Function() onComplete;
  final Future<void> Function() onSkip;
  final bool showBack;
  @override
  State<ClubJoinPage> createState() => _ClubJoinPageState();
}

class _ClubJoinPageState extends State<ClubJoinPage> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join({bool skip = false}) async {
    if (_busy) return;
    if (!skip && _code.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter your club joining code.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (skip) {
        await widget.onSkip();
      } else {
        final result = Map<String, dynamic>.from(
          await widget.client.rpc('join_club', params: {'p_code': _code.text})
              as Map,
        );
        if (result['ok'] != true) {
          throw AuthException(
            result['error'] as String? ?? 'Unable to join this club.',
          );
        }
        await widget.onComplete();
      }
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
    showBack: widget.showBack,
    title: 'Find your running people.',
    subtitle:
        'Enter the joining code shared by your club. You can also join later.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) FormNotice(_error!, error: true),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'Club joining code'),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: Text(_busy ? 'Please wait…' : 'Join my club'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _join(skip: true),
          child: const Text('Continue without a club'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Membership never shares your private training automatically. '
          'You control which runs your club can see.',
        ),
      ],
    ),
  );
}

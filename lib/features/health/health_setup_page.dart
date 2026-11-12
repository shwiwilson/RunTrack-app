import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';

/// User-confirmed native setup is distinct from a backend-verified provider link.
class HealthSetupPage extends StatefulWidget {
  const HealthSetupPage({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<HealthSetupPage> createState() => _HealthSetupPageState();
}

class _HealthSetupPageState extends State<HealthSetupPage>
    with WidgetsBindingObserver {
  static const _companions = <String, String>{
    'Garmin': 'Garmin Connect',
    'COROS': 'COROS',
    'Polar': 'Polar Flow',
    'Suunto': 'Suunto',
    'Apple Watch': 'Apple Health',
    'Samsung': 'Samsung Health',
    'Fitbit / Pixel Watch': 'Google Health',
    'Other': '',
  };
  static const _support = <String, String>{
    'Garmin': 'https://www.garmin.com/en-GB/software/garmin-connect/',
    'COROS': 'https://coros.com/coros-app',
    'Polar': 'https://flow.polar.com/',
    'Suunto': 'https://www.suunto.com/Content-pages/suunto-app/',
    'Apple Watch':
        'https://support.apple.com/guide/watch/stay-healthy-with-apple-watch-apd7dbb8f5a3/watchos',
    'Samsung': 'https://www.samsung.com/uk/apps/samsung-health/',
    'Fitbit / Pixel Watch': 'https://support.google.com/googlehealth/',
    'Other': 'https://support.google.com/googlehealth/answer/14236613',
  };
  String _phone = 'iPhone', _watch = 'Garmin';
  String _savedAt = '1970-01-01T00:00:00Z';
  final _companion = TextEditingController(text: 'Garmin Connect');
  int _step = 0;
  bool _nativeReady = false, _googleReady = false, _busy = true;
  String? _message;
  Map<String, dynamic>? _connection;
  String get _key => 'health_setup_${widget.client.auth.currentUser!.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _companion.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(
        _refreshStatus().catchError((Object _) {
          if (mounted) {
            setState(
              () => _message =
                  'Connection status could not be refreshed. Retry when online.',
            );
          }
        }),
      );
    }
    if (state == AppLifecycleState.inactive && !_busy) {
      unawaited(_save().catchError((Object _) {}));
    }
  }

  Map<String, dynamic> get _progress => {
    'phone': _phone,
    'watch': _watch,
    'companion': _companion.text,
    'step': _step,
    'native_ready': _nativeReady,
    'google_ready': _googleReady,
    'saved_at': _savedAt,
  };
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString(_key);
      Map<String, dynamic> progress = local == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(local) as Map);
      final profile = await widget.client
          .from('profiles')
          .select('onboarding')
          .eq('id', widget.client.auth.currentUser!.id)
          .single();
      final remote = (profile['onboarding'] as Map?)?['health_setup'];
      if (remote is Map &&
          (remote['saved_at']?.toString() ?? '').compareTo(
                progress['saved_at']?.toString() ?? '',
              ) >=
              0) {
        progress = Map<String, dynamic>.from(remote);
      }
      if (!mounted) return;
      setState(() {
        _savedAt = progress['saved_at'] as String? ?? '1970-01-01T00:00:00Z';
        _phone = ['iPhone', 'Android'].contains(progress['phone'])
            ? progress['phone'] as String
            : 'iPhone';
        _watch = _companions.containsKey(progress['watch'])
            ? progress['watch'] as String
            : 'Garmin';
        _companion.text =
            progress['companion'] as String? ?? _companions[_watch]!;
        _step = ((progress['step'] as num?)?.toInt() ?? 0).clamp(0, 3);
        _nativeReady = progress['native_ready'] == true;
        _googleReady = progress['google_ready'] == true;
      });
      await _refreshStatus();
      final result = Uri.base.queryParameters['health_result'];
      if (mounted && result != null) {
        setState(() {
          _step = 3;
          _message = switch (result) {
            'cancelled' =>
              'Google consent was cancelled. You can reconnect whenever you are ready.',
            'check_health_profile' =>
              'Check that your Google Health mobile profile is linked to the same Google Account, then reconnect. A running sync may also need a moment to finish.',
            'authorization_failed' =>
              'Google authorization could not finish or the request expired. Start the connection again.',
            'partial' =>
              'Check the verified connection status below. If a sync is incomplete, tap sync to continue.',
            'retry' =>
              'The connection needs attention. Check its status below and retry.',
            _ => null,
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Setup progress could not be loaded from RunTrack. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    _savedAt = DateTime.now().toUtc().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_progress));
    await widget.client.rpc(
      'update_onboarding',
      params: {
        'p_patch': {'health_setup': _progress},
      },
    );
  }

  Future<void> _refreshStatus() async {
    final connection = await widget.client
        .from('health_connections')
        .select('status,last_successful_sync_at,last_error,sync_cursor')
        .eq('user_id', widget.client.auth.currentUser!.id)
        .eq('provider', 'google_health')
        .maybeSingle();
    if (mounted) setState(() => _connection = connection);
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } on FunctionException catch (error) {
      if (mounted) {
        setState(
          () => _message =
              (error.details is Map ? (error.details as Map)['error'] : null)
                  ?.toString() ??
              'The running data service is unavailable. Check deployment setup or retry later.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The running data service could not complete this request. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    await _save();
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    )) {
      throw StateError('Could not open link');
    }
  }

  Future<void> _connect() async {
    await _save();
    final response = await widget.client.functions.invoke('health-connect');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['status'] == 'setup_required') {
      setState(() => _message = data['message'] as String);
      return;
    }
    final url = Uri.parse(data['authorization_url'] as String);
    if (url.scheme != 'https' || url.host != 'accounts.google.com') {
      throw StateError('Unexpected authorization URL');
    }
    // Same browsing context preserves the PWA return route; progress is already persisted.
    if (!await launchUrl(url, webOnlyWindowName: '_self')) {
      throw StateError('Could not open Google consent');
    }
  }

  Future<void> _sync() async {
    final response = await widget.client.functions.invoke('health-sync');
    final data = Map<String, dynamic>.from(response.data as Map);
    await _refreshStatus();
    if (!mounted) return;
    setState(
      () => _message = switch (data['status']) {
        'setup_required' =>
          'Google Health is awaiting secure deployment configuration. You can connect later.',
        'partial' =>
          'More workout history remains. Tap sync again to continue importing.',
        'synced' =>
          'Workout sync completed. ${data['imported']} running records checked. If no runs appeared, check that workouts are visible in Google Health.',
        _ => 'Sync could not finish. Check the connection details and retry.',
      },
    );
  }

  Widget _link(String label, String url) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _busy ? null : () => _run(() => _open(url)),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(label),
    ),
  );
  Widget _card(String title, String body, {List<Widget> children = const []}) =>
      PremiumCard(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(body),
          const SizedBox(height: 12),
          ...children,
        ],
      );
  @override
  Widget build(BuildContext context) {
    final iphone = _phone == 'iPhone';
    final status = _connection?['status'];
    return Scaffold(
      appBar: AppBar(title: const Text('Connect your running data')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Your runs, together.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect once, then let genuine workouts build your training history. You can finish later and keep using RunTrack.',
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: (_step + 1) / 4),
                const SizedBox(height: 8),
                Text('Step ${_step + 1} of 4'),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                if (_step == 0)
                  _card(
                    'Your phone and watch',
                    'Choose your setup. We cannot detect installed apps from your browser.',
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'iPhone',
                            label: Text('iPhone'),
                            icon: Icon(Icons.phone_iphone),
                          ),
                          ButtonSegment(
                            value: 'Android',
                            label: Text('Android'),
                            icon: Icon(Icons.phone_android),
                          ),
                        ],
                        selected: {_phone},
                        onSelectionChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _phone = value.first;
                                _nativeReady = false;
                              }),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        initialValue: _watch,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Watch brand',
                        ),
                        items: _companions.keys
                            .map(
                              (watch) => DropdownMenuItem(
                                value: watch,
                                child: Text(watch),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _watch = value!;
                                _companion.text = _companions[_watch]!;
                                _nativeReady = false;
                              }),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _companion,
                        decoration: const InputDecoration(
                          labelText: 'Watch companion app',
                        ),
                        enabled: !_busy,
                      ),
                      _link(
                        'Official watch app and support',
                        _support[_watch]!,
                      ),
                      if (_watch == 'Apple Watch' && !iphone)
                        const Text(
                          'Apple Watch setup requires an iPhone. Choose your iPhone to follow the supported Apple Health path.',
                        ),
                    ],
                  ),
                if (_step == 1)
                  _card(
                    iphone
                        ? 'Share workouts through Apple Health'
                        : 'Share workouts through Health Connect',
                    iphone
                        ? 'Sync your watch with ${_companion.text}. In that app’s health sharing settings, enable writing workouts and distance to Apple Health where supported. Check that a genuine run appears in Apple Health.'
                        : 'Sync your watch with ${_companion.text}. Enable writing exercise sessions and distance to Health Connect where your companion app supports it. Check a genuine run in Health Connect.',
                    children: [
                      if (!iphone)
                        const Text(
                          'Android 14 and later: Health Connect is in Settings → Security and privacy → Privacy controls. On earlier supported Android versions, install Health Connect if needed.',
                        ),
                      _link(
                        iphone
                            ? 'Apple Health guidance'
                            : 'Health Connect setup and permissions',
                        iphone
                            ? 'https://support.apple.com/guide/iphone/get-started-with-health-iphc959f9d3e/ios'
                            : 'https://support.google.com/android/answer/12201227',
                      ),
                      if (!iphone)
                        _link(
                          'Install Health Connect if needed',
                          'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata',
                        ),
                      const Text(
                        'Sharing varies by device and app. If your companion app cannot write workouts to this health app, this route may not provide runs. You can still use RunTrack and return later.',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _nativeReady,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _nativeReady = value!),
                        title: const Text(
                          'I checked my workout sharing settings',
                        ),
                        subtitle: const Text(
                          'This saves your progress; it does not verify a connection.',
                        ),
                      ),
                    ],
                  ),
                if (_step == 2)
                  _card(
                    'Set up Google Health',
                    'Install Google Health, sign in with your Google Account and create or link your health profile. Then connect ${iphone ? 'Apple Health' : 'Health Connect'} inside Google Health and choose which exercise data to share.',
                    children: [
                      Text(
                        iphone
                            ? 'Google Health → Connections → Apps and services → Apple Health. Follow the consent screens and permit reading workouts and distance.'
                            : 'Google Health → Connections → Partner apps → Sync your favorite health apps. Follow setup and permit reading exercise and distance from Health Connect.',
                      ),
                      _link(
                        'Install Google Health',
                        iphone
                            ? 'https://apps.apple.com/app/id462638897'
                            : 'https://play.google.com/store/apps/details?id=com.fitbit.FitbitMobile',
                      ),
                      _link(
                        'Official connection instructions',
                        iphone
                            ? 'https://support.google.com/googlehealth/answer/17037331'
                            : 'https://support.google.com/googlehealth/answer/14506680',
                      ),
                      const Text(
                        'Look for your running workout in Google Health. Workout details, history and laps depend on what your watch app shares. RunTrack requests read-only fitness access; location access is not required.',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _googleReady,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _googleReady = value!),
                        title: const Text(
                          'I opened Google Health and reviewed sharing',
                        ),
                        subtitle: const Text(
                          'Optional confirmation; the server checks your actual health account next.',
                        ),
                      ),
                    ],
                  ),
                if (_step == 3)
                  _card(
                    'Connect and check your workouts',
                    status == 'connected'
                        ? 'Google Health identity verified. Your connection status below comes from the server.'
                        : 'Approve Google’s read-only consent screen. RunTrack will verify your Google Health identity and attempt to retrieve genuine running workouts.',
                    children: [
                      Text(
                        'Status: ${switch (status) {
                          'connected' => 'Account linked',
                          'error' => 'Needs attention',
                          'revoked' => 'Permission revoked',
                          'disconnected' => 'Disconnected',
                          _ => 'No activity provider connected',
                        }}',
                      ),
                      if (_connection?['last_successful_sync_at'] != null)
                        Text(
                          'Last completed sync: ${DateTime.parse(_connection!['last_successful_sync_at'] as String).toLocal()}',
                        ),
                      if (_connection?['last_error'] != null)
                        Text(_connection!['last_error'] as String),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _run(_connect),
                        icon: const Icon(Icons.link),
                        label: Text(
                          status == 'connected'
                              ? 'Reconnect Google Health'
                              : 'Connect Google Health',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _run(_sync),
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync and check workouts'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _run(_refreshStatus),
                        child: const Text('Refresh connection status'),
                      ),
                      if (status != null && status != 'disconnected')
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  try {
                                    await widget.client.functions.invoke(
                                      'health-disconnect',
                                    );
                                  } finally {
                                    await _refreshStatus();
                                  }
                                  if (mounted) {
                                    setState(
                                      () => _message =
                                          'Google Health disconnected. Previously imported runs remain in your account.',
                                    );
                                  }
                                }),
                          child: const Text('Disconnect Google Health'),
                        ),
                      _link(
                        'Troubleshoot watch sharing',
                        'https://support.google.com/googlehealth/answer/14236613',
                      ),
                      const Text(
                        'No workouts? Confirm the same Google Account is used in both apps, check exercise permissions and sync your watch app. A linked account can have no workouts. If Google Health is awaiting deployment setup, you can finish later.',
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                setState(() => _step--);
                                await _save();
                              }),
                        child: const Text('Back'),
                      ),
                    if (_step < 3)
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                setState(() => _step++);
                                await _save();
                              }),
                        child: const Text('Continue'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await _save();
                              if (context.mounted) Navigator.of(context).pop();
                            }),
                      child: const Text('Finish later'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

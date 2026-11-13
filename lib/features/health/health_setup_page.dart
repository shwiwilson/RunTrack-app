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
  // Never restore a checkbox from saved setup progress or infer agreement.
  bool _healthConsentAccepted = false, _activeHealthConsent = false;
  static const _healthConsentVersion = '2026-11-12-v1';
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
    final consents = await widget.client
        .from('health_data_consents')
        .select('action,consent_version')
        .eq('user_id', widget.client.auth.currentUser!.id)
        .eq('provider', 'google_health')
        .order('id', ascending: false)
        .limit(1);
    if (mounted) {
      setState(() {
        _connection = connection;
        _activeHealthConsent =
            consents.isNotEmpty &&
            consents.first['action'] == 'granted' &&
            consents.first['consent_version'] == _healthConsentVersion;
      });
    }
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
    if (!_healthConsentAccepted) return;
    await _save();
    final response = await widget.client.functions.invoke(
      'health-connect',
      body: {
        'health_data_consent': true,
        'consent_version': _healthConsentVersion,
      },
    );
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

  Future<void> _finishLater() async {
    await _save();
    if (mounted) Navigator.of(context).pop();
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
  Widget _instruction(int number, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number. ', style: Theme.of(context).textTheme.titleMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final iphone = _phone == 'iPhone';
    final directGoogle = _watch == 'Fitbit / Pixel Watch';
    final healthApp = iphone ? 'Apple Health' : 'Health Connect';
    final companion = _companion.text.trim().isEmpty
        ? 'your watch app'
        : _companion.text.trim();
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
                  'Register and sign in to RunTrack with your email and password. You can join the club, use sessions and RSVP without connecting Google. Workout imports are optional; skip this and return later.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : () => _run(_finishLater),
                    child: const Text('Skip for now, use the club'),
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  'How your runs reach RunTrack',
                  directGoogle
                      ? 'Your watch → Google Health → RunTrack'
                      : 'Your watch → $companion → $healthApp → Google Health → RunTrack',
                  children: const [
                    Text(
                      'RunTrack is this website, even when you add it to your home screen. Set up sharing in the separate phone apps first. RunTrack then reads the running workouts available in your Google Health account.',
                    ),
                  ],
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
                    'Choose the phone that syncs with your watch. The steps below change to match it. Your browser cannot check which phone apps you have installed.',
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
                    directGoogle
                        ? 'Sync your watch to Google Health'
                        : iphone
                        ? 'Share workouts through Apple Health'
                        : 'Share workouts through Health Connect',
                    directGoogle
                        ? 'Your watch uses Google Health directly. You can skip the extra Apple Health or Health Connect bridge for workouts recorded by this watch.'
                        : 'First move one real run from $companion into $healthApp. Connecting RunTrack alone cannot move data out of your watch app.',
                    children: [
                      _instruction(
                        1,
                        'Sync a recorded run',
                        'Open $companion on your phone and sync your watch. Check that the run appears there before continuing.',
                      ),
                      if (!directGoogle)
                        _instruction(
                          2,
                          'Allow your watch app to share fitness data',
                          _watch == 'Garmin' && !iphone
                              ? 'Garmin sharing with Health Connect requires Android 14 or later. Search your phone settings for Health Connect, open app permissions and allow Garmin Connect to write the supported fitness data. Garmin sends data after a successful watch sync; it does not read data back from Health Connect.'
                              : _watch == 'Garmin' && iphone
                              ? 'In Apple Health, open your profile, find Apps and Services under Privacy, then choose Connect. Enable Workouts and Walking + Running Distance where available. Keep Garmin Connect open while syncing your watch.'
                              : 'In $companion, find health sharing or connected apps and allow writing workouts and distance to $healthApp where supported. In $healthApp, check that this app has permission to write those data types.',
                        ),
                      if (!directGoogle)
                        _instruction(
                          3,
                          'Check the receiving health app',
                          'Look for the run or its exercise data in $healthApp. If it is missing, fix this sharing step first. RunTrack cannot retrieve data that has not reached Google Health.',
                        ),
                      if (_watch == 'Garmin' && !directGoogle)
                        _link(
                          'Garmin: share with $healthApp',
                          iphone
                              ? 'https://support.garmin.com/en-GB/?faq=lK5FPB9iPF5PXFkIpFlFPA'
                              : 'https://support.garmin.com/en-GB/?faq=JToBEy0jfe6pIygark2Ui5',
                        ),
                      if (!directGoogle)
                        _link(
                          iphone
                              ? 'Apple Health guidance'
                              : 'Health Connect setup and permissions',
                          iphone
                              ? 'https://support.apple.com/guide/iphone/get-started-with-health-iphc959f9d3e/ios'
                              : 'https://support.google.com/android/answer/12201227',
                        ),
                      if (!iphone && !directGoogle && _watch != 'Garmin')
                        _link(
                          'Install Health Connect if needed',
                          'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata',
                        ),
                      if (!directGoogle)
                        Text(
                          _watch == 'Garmin' && !iphone
                              ? 'Installing Health Connect on an older phone does not add Garmin’s Android 14 sharing support. If this route is unavailable, skip workout imports and use the club now.'
                              : 'Support varies by watch and app. If your app cannot share workouts through this route, skip workout imports and use the club now.',
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _nativeReady,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _nativeReady = value!),
                        title: const Text('I checked this step on my phone'),
                        subtitle: const Text(
                          'This saves your progress; it does not verify a connection.',
                        ),
                      ),
                    ],
                  ),
                if (_step == 2)
                  _card(
                    'Set up Google Health',
                    'Install the Google Health phone app and sign in with an adult Google Account. Finish creating or linking your health profile. You do not need a Google watch or a Google login for your RunTrack registration.',
                    children: [
                      if (!directGoogle)
                        _instruction(
                          1,
                          'Connect $healthApp inside Google Health',
                          iphone
                              ? 'Open Connections, then Apps and services, and choose Apple Health. Complete setup and allow Google Health to read exercise and distance. Select only the data you want to share.'
                              : 'Open Connections, then Partner apps, and set up Sync your favorite health apps. Choose fitness data and let Google Health read exercise and distance from Health Connect, plus heart rate if wanted. Medical records are not needed. Review optional history and background access for ongoing syncing.',
                        ),
                      _instruction(
                        directGoogle ? 1 : 2,
                        'Find your run in Google Health',
                        'Check that a real running workout appears in the Google Health app before connecting RunTrack. Use this same Google Account on RunTrack’s Google permission screen. It can be different from your RunTrack registration email.',
                      ),
                      _link(
                        'Install Google Health',
                        iphone
                            ? 'https://apps.apple.com/app/id462638897'
                            : 'https://play.google.com/store/apps/details?id=com.fitbit.FitbitMobile',
                      ),
                      _link(
                        'Official connection instructions',
                        directGoogle
                            ? 'https://support.google.com/googlehealth/answer/14236613'
                            : iphone
                            ? 'https://support.google.com/googlehealth/answer/17037331'
                            : 'https://support.google.com/googlehealth/answer/14506680',
                      ),
                      if (!iphone && !directGoogle)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'To check the bridge: in Google Health, open Connections → Partner apps → Manage Health Connect. Look for a recent sync time, or tap Sync at the top right.',
                          ),
                        ),
                      Text(
                        _watch == 'Garmin'
                            ? 'Garmin’s route provides exercise summaries; detailed lap splits and routes are not shared through this route. Older history and heart-rate detail can be limited. Start by checking a newly synced run.'
                            : 'History, heart rate and lap detail depend on what each app actually shares. A successful connection does not guarantee older runs or every workout field will be available.',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _googleReady,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _googleReady = value!),
                        title: const Text(
                          'I checked for my running workout in Google Health',
                        ),
                        subtitle: const Text(
                          'This saves progress only. It does not connect RunTrack or give it health-data permission.',
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
                      const Text(
                        'Pilot access: Google connections currently need an approved Google Account. If Google blocks access, email hello@tswebdev.co.uk with the Google Account address you want to connect. You can keep using RunTrack while waiting.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'During Google testing, permission may expire after 7 days. If syncing stops and permission is revoked, return here and reconnect. Your RunTrack email login and club access continue.',
                      ),
                      _link(
                        'Email pilot support',
                        'mailto:hello@tswebdev.co.uk',
                      ),
                      const SizedBox(height: 12),
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
                      if (status == 'connected' && !_activeHealthConsent)
                        const Text(
                          'Review the health data consent and reconnect before syncing more workouts.',
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _healthConsentAccepted,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _healthConsentAccepted = value == true,
                              ),
                        title: const Text(
                          'I explicitly consent to RunTrack reading my Google Health exercise data and storing my running workouts, including times, distance and available heart rate, to import and sync my training history.',
                        ),
                        subtitle: const Text(
                          'This is optional. I can withdraw consent by disconnecting Google Health. Imported runs remain in my account and stay private unless I choose to share them.',
                        ),
                      ),
                      _link(
                        'Read the privacy notice',
                        Uri.base.resolve('/privacy.html').toString(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy || !_healthConsentAccepted
                            ? null
                            : () async => _run(_connect),
                        icon: const Icon(Icons.link),
                        label: Text(
                          status == 'connected'
                              ? 'Reconnect Google Health'
                              : 'Connect Google Health',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy || !_activeHealthConsent
                            ? null
                            : () => _run(_sync),
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync and check workouts'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _run(_refreshStatus),
                        child: const Text('Refresh connection status'),
                      ),
                      if (_activeHealthConsent ||
                          (status != null && status != 'disconnected'))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  try {
                                    await widget.client.functions.invoke(
                                      'health-disconnect',
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _healthConsentAccepted = false,
                                      );
                                    }
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
                        'No runs yet? Work backwards: find the run in Google Health, then in Apple Health or Health Connect, then in your watch app. Sync the watch and check each app’s permissions. A linked account can have no runs; contact pilot support if access is blocked or the service is not ready.',
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
                      onPressed: _busy ? null : () => _run(_finishLater),
                      child: const Text('Skip for now, use the club'),
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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:run_track_app/core/config/app_config.dart';
import 'package:run_track_app/core/theme/run_track_theme.dart';
import 'package:run_track_app/features/auth/auth_page.dart';
import 'package:run_track_app/main.dart';

String jwtForRole(String role) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test('successful Google Health returns land in the app shell', () {
    expect(
      healthReturnLandingNotice('linked'),
      'Google Health is connected. Your latest workouts have been checked.',
    );
    expect(
      healthReturnLandingNotice('partial'),
      'Google Health is connected. Some older workout history is still available to sync.',
    );
    expect(healthReturnLandingNotice('cancelled'), isNull);
    expect(healthReturnLandingNotice('authorization_failed'), isNull);
  });

  testWidgets(
    'invalid join codes stay on the form and never advance onboarding',
    (tester) async {
      var completed = false;
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: MemoryPkceStorage(),
          ),
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'ok': false,
                'code': 'invalid_code',
                'error': 'Invalid club joining code.',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        ),
      ))!;
      addTearDown(() => tester.runAsync(client.dispose));
      await tester.pumpWidget(
        MaterialApp(
          home: ClubJoinPage(
            client: client,
            onComplete: () async {
              completed = true;
            },
            onSkip: () async {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'wrong-code');
      await tester.runAsync(
        tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Join my club'),
                )
                .onPressed!
            as Future<void> Function(),
      );
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(find.text('Invalid club joining code.'), findsOneWidget);
    },
  );
  test('browser configuration rejects secrets and unsafe remote HTTP', () {
    for (final key in [
      'sb_secret_hidden',
      jwtForRole('service_role'),
      '',
      'bad-key',
    ]) {
      expect(
        AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          publishableKey: key,
        ).validationError,
        isNotNull,
      );
    }
    expect(
      const AppConfig(
        supabaseUrl: 'http://example.com',
        publishableKey: 'sb_publishable_public',
      ).validationError,
      isNotNull,
    );
    expect(
      AppConfig(
        supabaseUrl: 'http://127.0.0.1:56321',
        publishableKey: jwtForRole('anon'),
      ).validationError,
      isNull,
    );
    expect(
      const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_public',
      ).validationError,
      isNull,
    );
  });

  testWidgets('missing deployment configuration is a useful screen on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RunTrackApp());
    expect(find.text('Getting RunTrack ready.'), findsOneWidget);
    expect(find.textContaining('Supabase configuration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration submits actual form fields to Auth and requires verification',
    (tester) async {
      http.Request? signup;
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: MemoryPkceStorage(),
          ),
          httpClient: MockClient((request) async {
            signup = request;
            return http.Response(
              jsonEncode({
                'id': '00000000-0000-4000-8000-000000000001',
                'email': 'runner@example.test',
                'aud': 'authenticated',
                'created_at': '2026-11-12T10:00:00Z',
                'user_metadata': {'display_name': 'Real Runner'},
                'identities': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        ),
      ))!;
      addTearDown(() => tester.runAsync(client.dispose));
      await tester.pumpWidget(
        MaterialApp(
          theme: runTrackTheme(Brightness.light),
          home: AuthPage(client: client, bootstrapPending: true),
        ),
      );
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        'Real Runner',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        ' runner@example.test ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'a-long-test-password',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.runAsync(
        tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Create account'),
                )
                .onPressed!
            as Future<void> Function(),
      );
      await tester.pumpAndSettle();
      expect(
        signup?.url.path,
        '/auth/v1/signup',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      final body = jsonDecode(signup!.body) as Map;
      expect(body['email'], 'runner@example.test');
      expect(body['data'], {'display_name': 'Real Runner'});
      expect(body.containsKey('role'), isFalse);
      expect(client.auth.currentSession, isNull);
      expect(
        find.textContaining('Check your email to verify your account'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'password recovery calls Auth without exposing whether an account exists',
    (tester) async {
      http.Request? recovery;
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          authOptions: AuthClientOptions(
            autoRefreshToken: false,
            pkceAsyncStorage: MemoryPkceStorage(),
          ),
          httpClient: MockClient((request) async {
            recovery = request;
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        ),
      ))!;
      addTearDown(() => tester.runAsync(client.dispose));
      await tester.pumpWidget(
        MaterialApp(home: AuthPage(client: client, bootstrapPending: false)),
      );
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'runner@example.test',
      );
      await tester.runAsync(
        tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Send reset link'),
                )
                .onPressed!
            as Future<void> Function(),
      );
      await tester.pumpAndSettle();
      expect(
        recovery?.url.path,
        '/auth/v1/recover',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(
        find.textContaining('If this email has an account'),
        findsOneWidget,
      );
      expect(client.auth.currentSession, isNull);
    },
  );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:run_track_app/features/health/health_setup_page.dart';
import '../auth_and_config_test.dart' show MemoryPkceStorage;

void main() {
  testWidgets('connecting requires a fresh unchecked explicit health consent', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    SharedPreferences.setMockInitialValues({
      'health_setup_fixture-user': jsonEncode({
        'step': 3,
        'saved_at': '2026-11-12T00:00:00Z',
        'health_data_consent': true,
      }),
    });
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
        httpClient: MockClient((request) async {
          final Object? result;
          if (request.url.path.endsWith('/profiles')) {
            result = {'onboarding': {}};
          } else if (request.url.path.endsWith('/health_connections')) {
            result = {'status': 'connected', 'sync_cursor': {}};
          } else if (request.url.path.endsWith('/health_data_consents')) {
            result = [
              {'action': 'granted', 'consent_version': '2026-11-12-v1'},
            ];
          } else if (request.url.path.endsWith('/health-connect')) {
            submitted = Map<String, dynamic>.from(
              jsonDecode(request.body) as Map,
            );
            result = {
              'status': 'setup_required',
              'message': 'Configure Google Health',
            };
          } else {
            result = null;
          }
          return http.Response(
            jsonEncode(result),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      ),
    ))!;
    await tester.runAsync(
      () => client.auth.recoverSession(
        jsonEncode({
          'access_token': 'test-only-session',
          'token_type': 'bearer',
          'user': {'id': 'fixture-user', 'email': 'fixture@example.test'},
        }),
      ),
    );
    addTearDown(() => tester.runAsync(client.dispose));
    await tester.pumpWidget(MaterialApp(home: HealthSetupPage(client: client)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Reconnect Google Health');
    final checkbox = find.widgetWithText(
      CheckboxListTile,
      'I explicitly consent to RunTrack reading my Google Health exercise data and storing my running workouts, including times, distance and available heart rate, to import and sync my training history.',
    );
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text('Read the privacy notice'), findsOneWidget);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.runAsync(
      tester.widget<FilledButton>(button).onPressed! as Future<void> Function(),
    );
    await tester.pumpAndSettle();
    expect(
      submitted,
      {'health_data_consent': true, 'consent_version': '2026-11-12-v1'},
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    expect(tester.takeException(), isNull);
  });
}

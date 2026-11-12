import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:run_track_app/data/repositories/supabase_run_track_repository.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const clubId = '00000000-0000-4000-8000-000000000002';
http.Response response(Object? json, {int status = 200}) => http.Response(
  jsonEncode(json),
  status,
  headers: {'content-type': 'application/json'},
);
Future<SupabaseClient> clientFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final result = await handler(request);
      return http.Response.bytes(
        result.bodyBytes,
        result.statusCode,
        headers: result.headers,
        request: request,
      );
    }),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'test-only-token',
      'token_type': 'bearer',
      'refresh_token': 'test-only-refresh',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'email': 'fixture@example.test',
        'created_at': '2026-11-12T10:00:00Z',
      },
    }),
  );
  return client;
}

Map<String, dynamic> row(int index) => {
  'id': 'activity-$index',
  'user_id': userId,
  'provider': 'test_only',
  'provider_workout_id': 'workout-$index',
  'type': 'running',
  'started_at': '2026-11-10T09:00:00Z',
  'ended_at': '2026-11-10T09:30:00Z',
  'distance_m': 5000,
  'active_duration_s': 1500,
  'elapsed_duration_s': 1800,
};

void main() {
  test(
    'repository paginates complete own history without creating a club or missing metrics',
    () async {
      final activityRequests = <http.Request>[];
      final client = await clientFor((request) async {
        final table = request.url.pathSegments.last;
        if (table == 'profiles') {
          return response({'id': userId, 'display_name': 'Test fixture'});
        }
        if (table == 'activities') {
          activityRequests.add(request);
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          return response(offset == 0 ? List.generate(500, row) : [row(500)]);
        }
        return response([]);
      });
      addTearDown(client.dispose);
      final data = await SupabaseRunTrackRepository(client).load();
      expect(data.membership, isNull);
      expect(data.activities.length, 501);
      expect(data.activities.first.averageHeartRate, isNull);
      expect(activityRequests.length, 2);
      for (final request in activityRequests) {
        expect(request.url.queryParameters['user_id'], 'eq.$userId');
        expect(request.url.queryParameters['duplicate_of'], 'is.null');
        expect(request.url.queryParameters['select'], '*,activity_laps(*)');
        expect(
          request.url.queryParameters['order'],
          'started_at.desc.nullslast,id.desc.nullslast',
        );
      }
      expect(activityRequests.last.url.queryParameters['offset'], '500');
    },
  );
  test(
    'club feed uses sanitized server RPC, never broad cross-user activity reads',
    () async {
      final requests = <http.Request>[];
      final client = await clientFor((request) async {
        requests.add(request);
        switch (request.url.pathSegments.last) {
          case 'profiles':
            return response({'id': userId, 'display_name': 'Test fixture'});
          case 'club_memberships':
            return response([
              {
                'id': 'membership',
                'user_id': userId,
                'club_id': clubId,
                'role': 'athlete',
                'status': 'active',
                'clubs': {'name': 'Test club', 'theme_json': {}},
              },
            ]);
          case 'shared_activity_feed':
            return response([
              {
                ...row(1),
                'user_id': 'another-user',
                'visibility': 'club',
                'shared_club_id': clubId,
              },
            ]);
          case 'club_member_profiles':
            return response([
              {'id': userId, 'display_name': 'Test fixture'},
            ]);
          default:
            return response([]);
        }
      });
      addTearDown(client.dispose);
      final data = await SupabaseRunTrackRepository(client).load();
      expect(data.clubActivities.single.userId, 'another-user');
      expect(data.clubActivities.single.averageHeartRate, isNull);
      final activities = requests.where(
        (r) => r.url.pathSegments.last == 'activities',
      );
      expect(activities.length, 1);
      expect(activities.single.url.queryParameters['user_id'], 'eq.$userId');
      final rpc = requests.singleWhere(
        (r) => r.url.pathSegments.last == 'shared_activity_feed',
      );
      expect(jsonDecode(rpc.body), {'p_club_id': clubId});
    },
  );
  test(
    'activity sharing sends visibility fields only; source measurements cannot be overwritten',
    () async {
      http.Request? mutation;
      final client = await clientFor((request) async {
        mutation = request;
        return response({'id': 'activity'});
      });
      addTearDown(client.dispose);
      await SupabaseRunTrackRepository(
        client,
      ).shareActivity('activity', clubId);
      expect(mutation!.method, 'PATCH');
      expect(mutation!.url.queryParameters['user_id'], 'eq.$userId');
      expect(jsonDecode(mutation!.body), {
        'visibility': 'club',
        'shared_club_id': clubId,
      });
    },
  );
  test('RSVP update cannot modify attendee identity or attendance', () async {
    final requests = <http.Request>[];
    final client = await clientFor((request) async {
      requests.add(request);
      return response(request.method == 'GET' ? {'id': 'rsvp'} : {});
    });
    addTearDown(client.dispose);
    await SupabaseRunTrackRepository(client).rsvp('session', true);
    final mutation = requests.singleWhere((r) => r.method == 'PATCH');
    expect(jsonDecode(mutation.body), {'status': 'going'});
    expect(mutation.url.queryParameters['id'], 'eq.rsvp');
  });
  test(
    'attendance uses authorized RPC instead of browser column grants',
    () async {
      http.Request? mutation;
      final client = await clientFor((request) async {
        mutation = request;
        return response(null);
      });
      addTearDown(client.dispose);
      await SupabaseRunTrackRepository(client).confirmAttendance('rsvp', true);
      expect(mutation!.url.path, '/rest/v1/rpc/record_attendance');
      expect(jsonDecode(mutation!.body), {
        'p_rsvp_id': 'rsvp',
        'p_attended': true,
      });
    },
  );
  test(
    'database errors propagate and never fall back to generated records',
    () async {
      final client = await clientFor(
        (request) async => response({
          'code': '42501',
          'message': 'permission denied',
        }, status: 403),
      );
      addTearDown(client.dispose);
      expect(
        SupabaseRunTrackRepository(client).load(),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
  test(
    'new race results never send a verification claim or other user id',
    () async {
      http.Request? mutation;
      final client = await clientFor((request) async {
        mutation = request;
        return response({});
      });
      addTearDown(client.dispose);
      await SupabaseRunTrackRepository(client).addRaceResult(
        eventName: ' Test race ',
        eventDate: DateTime(2026, 11, 1),
        distanceM: 5000,
        durationS: 1500,
      );
      final body = jsonDecode(mutation!.body) as Map;
      expect(body['user_id'], userId);
      expect(body['event_name'], 'Test race');
      expect(body['event_date'], '2026-11-01');
      expect(body.containsKey('verified'), isFalse);
    },
  );
  test(
    'confirmed attendance survives leaving a club without revealing old club records',
    () async {
      http.Request? attendanceRequest;
      final client = await clientFor((request) async {
        final table = request.url.pathSegments.last;
        if (table == 'profiles') {
          return response({'id': userId, 'display_name': 'Test fixture'});
        }
        if (table == 'session_rsvps') {
          attendanceRequest = request;
          return response([
            {
              'id': 'old-rsvp',
              'session_id': 'old-session',
              'user_id': userId,
              'status': 'going',
              'attended': true,
            },
          ]);
        }
        return response([]);
      });
      addTearDown(client.dispose);
      final data = await SupabaseRunTrackRepository(client).load();
      expect(data.membership, isNull);
      expect(data.sessions, isEmpty);
      expect(data.attendanceCount, 1);
      expect(attendanceRequest!.url.queryParameters['user_id'], 'eq.$userId');
      expect(attendanceRequest!.url.queryParameters['attended'], 'eq.true');
      expect(
        RunningAchievement.calculate(
          data.activities,
          now: DateTime(2026, 11, 12),
          attendedSessions: data.attendanceCount,
        ).singleWhere((a) => a.id == 'club_first').earned,
        isTrue,
      );
    },
  );
}

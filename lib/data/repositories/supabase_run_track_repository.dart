import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

/// Every mutation is checked again by RLS or a trusted database function.
/// No cache, generated records or offline success paths replace the database.
class SupabaseRunTrackRepository implements RunTrackRepository {
  SupabaseRunTrackRepository(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;

  Future<List<Map<String, dynamic>>> _all(
    String table, {
    String select = '*',
    Map<String, Object> equals = const {},
    String? order,
    bool canonicalActivities = false,
  }) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      dynamic query = client.from(table).select(select);
      for (final filter in equals.entries) {
        query = query.eq(filter.key, filter.value);
      }
      if (canonicalActivities) query = query.isFilter('duplicate_of', null);
      query = query.order(order ?? 'id');
      if (order != null && order != 'id') query = query.order('id');
      final page = List<Map<String, dynamic>>.from(
        await query.range(offset, offset + pageSize - 1) as List,
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows;
  }

  @override
  Future<RunTrackSnapshot> load() async {
    final profile = AthleteProfile.fromJson(
      await client
          .from('profiles')
          .select('id,display_name')
          .eq('id', userId)
          .single(),
    );
    final memberships = (await _all(
      'club_memberships',
      select: '*,clubs(id,name,theme_json)',
      equals: {'user_id': userId},
    )).map(ClubMembership.fromJson).toList();
    final membership = memberships
        .where((m) => m.status == 'active')
        .firstOrNull;
    final ownResults = await Future.wait([
      _all(
        'activities',
        select: '*,activity_laps(*)',
        equals: {'user_id': userId},
        order: 'started_at',
        canonicalActivities: true,
      ),
      _all('race_results', equals: {'user_id': userId}, order: 'event_date'),
      _all('health_connections', equals: {'user_id': userId}),
      _all('session_rsvps', equals: {'user_id': userId, 'attended': true}),
    ]);
    var sessions = <ClubSession>[];
    var challenges = <ClubChallenge>[];
    var clubActivities = <Activity>[];
    var clubMembers = <ClubMembership>[];
    var names = <String, String>{};
    if (membership != null) {
      final clubResults = await Future.wait([
        _all(
          'club_sessions',
          select: '*,session_rsvps(*)',
          equals: {'club_id': membership.clubId},
          order: 'starts_at',
        ),
        _all(
          'club_challenges',
          select: '*,challenge_participants(*)',
          equals: {'club_id': membership.clubId},
          order: 'starts_at',
        ),
        _sharedActivities(membership.clubId),
        _all(
          'club_memberships',
          select: '*,clubs(id,name,theme_json)',
          equals: {'club_id': membership.clubId},
        ),
      ]);
      sessions = clubResults[0].map(ClubSession.fromJson).toList();
      challenges = clubResults[1]
          .map((e) => ClubChallenge.fromJson(e, userId))
          .toList();
      clubActivities = clubResults[2].map(Activity.fromJson).toList();
      clubMembers = clubResults[3].map(ClubMembership.fromJson).toList();
      final profiles = await client.rpc(
        'club_member_profiles',
        params: {'p_club_id': membership.clubId},
      );
      names = {
        for (final p in profiles as List)
          p['id'] as String: p['display_name'] as String,
      };
    }
    return RunTrackSnapshot(
      profile: profile,
      memberships: memberships,
      activities: ownResults[0].map(Activity.fromJson).toList(),
      raceResults: ownResults[1].map(RaceResult.fromJson).toList(),
      connections: ownResults[2].map(HealthConnection.fromJson).toList(),
      clubActivities: clubActivities,
      sessions: sessions,
      challenges: challenges,
      memberNames: names,
      clubMembers: clubMembers,
      confirmedAttendanceCount: ownResults[3].length,
    );
  }

  Future<List<Map<String, dynamic>>> _sharedActivities(String clubId) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = List<Map<String, dynamic>>.from(
        await client
                .rpc('shared_activity_feed', params: {'p_club_id': clubId})
                .order('started_at')
                .order('id')
                .range(offset, offset + 499)
            as List,
      );
      result.addAll(page);
      if (page.length < 500) break;
    }
    return result;
  }

  @override
  Future<void> shareActivity(String id, String? clubId) async {
    await client
        .from('activities')
        .update({
          'visibility': clubId == null ? 'private' : 'club',
          'shared_club_id': clubId,
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select('id')
        .single();
  }

  @override
  Future<void> rsvp(String sessionId, bool going) async {
    final existing = await client
        .from('session_rsvps')
        .select('id')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    final status = going ? 'going' : 'cancelled';
    if (existing == null) {
      await client.from('session_rsvps').insert({
        'session_id': sessionId,
        'user_id': userId,
        'status': status,
      });
    } else {
      await client
          .from('session_rsvps')
          .update({'status': status})
          .eq('id', existing['id']);
    }
  }

  @override
  Future<void> saveSession({
    String? id,
    required String clubId,
    required String title,
    required String details,
    required String location,
    required DateTime startsAt,
  }) async {
    final row = {
      'title': title.trim(),
      'details': details.trim(),
      'location': location.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
    };
    if (id == null) {
      await client.from('club_sessions').insert({
        ...row,
        'club_id': clubId,
        'created_by': userId,
      });
    } else {
      await client
          .from('club_sessions')
          .update(row)
          .eq('id', id)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> deleteSession(String id) async =>
      await client.from('club_sessions').delete().eq('id', id);
  @override
  Future<void> confirmAttendance(String rsvpId, bool attended) async {
    await client.rpc(
      'record_attendance',
      params: {'p_rsvp_id': rsvpId, 'p_attended': attended},
    );
  }

  @override
  Future<void> updateMember(
    ClubMembership membership,
    String status,
    String role,
  ) async {
    await client.rpc(
      'update_membership',
      params: {
        'p_membership_id': membership.id,
        'p_status': status,
        'p_role': role,
      },
    );
  }

  @override
  Future<void> rotateCode(String clubId, String code) async {
    await client.rpc(
      'rotate_join_code',
      params: {'p_club_id': clubId, 'p_code': code.trim()},
    );
  }

  @override
  Future<void> updateClub(String clubId, String name) async {
    await client
        .from('clubs')
        .update({'name': name.trim()})
        .eq('id', clubId)
        .select('id')
        .single();
  }

  @override
  Future<void> saveChallenge({
    String? id,
    required String clubId,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required double targetDistanceM,
  }) async {
    final row = {
      'title': title.trim(),
      'description': description.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'target_distance_m': targetDistanceM,
    };
    if (id == null) {
      await client.from('club_challenges').insert({...row, 'club_id': clubId});
    } else {
      await client
          .from('club_challenges')
          .update(row)
          .eq('id', id)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> deleteChallenge(String id) async =>
      await client.from('club_challenges').delete().eq('id', id);
  @override
  Future<void> addRaceResult({
    required String eventName,
    required DateTime eventDate,
    required double distanceM,
    required double durationS,
    String? evidenceUrl,
  }) async {
    await client.from('race_results').insert({
      'user_id': userId,
      'event_name': eventName.trim(),
      'event_date':
          '${eventDate.year.toString().padLeft(4, '0')}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
      'distance_m': distanceM,
      'duration_s': durationS,
      'evidence_url': evidenceUrl,
    });
  }

  @override
  Future<void> deleteRaceResult(String id) async {
    await client
        .from('race_results')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }

  @override
  Future<void> participate(String challengeId, bool join) async {
    if (join) {
      await client.from('challenge_participants').insert({
        'challenge_id': challengeId,
        'user_id': userId,
      });
    } else {
      await client
          .from('challenge_participants')
          .delete()
          .eq('challenge_id', challengeId)
          .eq('user_id', userId);
    }
  }
}

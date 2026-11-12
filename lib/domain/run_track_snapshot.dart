import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

class RunTrackSnapshot {
  const RunTrackSnapshot({
    required this.profile,
    required this.memberships,
    required this.activities,
    required this.clubActivities,
    required this.sessions,
    required this.challenges,
    required this.raceResults,
    required this.connections,
    required this.memberNames,
    required this.clubMembers,
    this.confirmedAttendanceCount = 0,
  });
  final AthleteProfile profile;
  final List<ClubMembership> memberships;
  final List<Activity> activities;
  final List<Activity> clubActivities;
  final List<ClubSession> sessions;
  final List<ClubChallenge> challenges;
  final List<RaceResult> raceResults;
  final List<HealthConnection> connections;
  final Map<String, String> memberNames;
  final List<ClubMembership> clubMembers;

  /// Count of the athlete's own server-confirmed RSVPs, including former clubs.
  final int confirmedAttendanceCount;
  ClubMembership? get membership =>
      memberships.where((m) => m.status == 'active').firstOrNull;
  int get attendanceCount => confirmedAttendanceCount;
}

class HealthConnection {
  const HealthConnection({
    required this.provider,
    required this.status,
    this.lastSuccessfulSyncAt,
    this.lastError,
  });
  final String provider;
  final String status;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastError;
  factory HealthConnection.fromJson(Map<String, dynamic> json) =>
      HealthConnection(
        provider: json['provider'] as String,
        status: json['status'] as String,
        lastSuccessfulSyncAt: DateTime.tryParse(
          json['last_successful_sync_at'] as String? ?? '',
        ),
        lastError: json['last_error'] as String?,
      );
}

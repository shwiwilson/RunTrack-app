import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

abstract interface class RunTrackRepository {
  Future<RunTrackSnapshot> load();
  Future<void> shareActivity(String id, String? clubId);
  Future<void> rsvp(String sessionId, bool going);
  Future<void> saveSession({
    String? id,
    required String clubId,
    required String title,
    required String details,
    required String location,
    required DateTime startsAt,
  });
  Future<void> deleteSession(String id);
  Future<void> confirmAttendance(String rsvpId, bool attended);
  Future<void> updateMember(
    ClubMembership membership,
    String status,
    String role,
  );
  Future<void> rotateCode(String clubId, String code);
  Future<void> updateClub(String clubId, String name);
  Future<void> saveChallenge({
    String? id,
    required String clubId,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required double targetDistanceM,
  });
  Future<void> deleteChallenge(String id);
  Future<void> addRaceResult({
    required String eventName,
    required DateTime eventDate,
    required double distanceM,
    required double durationS,
    String? evidenceUrl,
  });
  Future<void> deleteRaceResult(String id);
  Future<void> participate(String challengeId, bool join);
}

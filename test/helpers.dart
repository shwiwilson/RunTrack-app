import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';

RunTrackSnapshot emptySnapshot({
  bool admin = false,
  List<Activity> activities = const [],
}) => RunTrackSnapshot(
  profile: const AthleteProfile(id: 'test-user', displayName: 'Test Runner'),
  memberships: admin
      ? [
          const ClubMembership(
            id: 'test-membership',
            clubId: 'test-club',
            userId: 'test-user',
            role: 'admin',
            status: 'active',
            clubName: 'Test club',
          ),
        ]
      : [],
  activities: activities,
  clubActivities: [],
  sessions: [],
  challenges: [],
  raceResults: [],
  connections: [],
  memberNames: {},
  clubMembers: [],
);

/// Test-only fixture repository; no production imports refer to this class.
class TestRepository implements RunTrackRepository {
  RunTrackSnapshot data = emptySnapshot();
  Object? failure;
  int loads = 0;
  @override
  Future<RunTrackSnapshot> load() async {
    loads++;
    if (failure != null) {
      throw failure!;
    }
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';

abstract class RunTrackRepository {
  Future<Map<String, dynamic>> fetchDefaultClubProfile();
  Future<YouTabState> fetchReadiness(String clubId, String athleteId);
  Future<List<ActivityFeedItem>> fetchActivities(String clubId);
  Future<List<ClubSessionItem>> fetchClubSessions(String clubId);
  Future<List<NewsletterStagingItem>> fetchNewsletterStaging(String clubId);
  Future<AchievementsState> fetchAchievements(String clubId);
  Future<void> updateRsvp(String sessionId, String athleteId, String status);
}

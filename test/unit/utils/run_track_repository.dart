import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

abstract class RunTrackRepository {
  List<ClubSessionItem> getSessions(String clubId);
  List<NewsletterStagingItem> getNewsletterStagingItems(String clubId);
}

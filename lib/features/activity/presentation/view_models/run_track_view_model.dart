import 'package:flutter/foundation.dart';
import 'package:run_track_app/data/repositories/mock_run_track_repository.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/activity/domain/models/activity_models.dart';
import 'package:run_track_app/data/repositories/time_range_toggle.dart';
export 'package:run_track_app/features/activity/domain/models/activity_models.dart';

class RunTrackViewModel extends ChangeNotifier {
  factory RunTrackViewModel({
    required RunTrackRepository repository,
    required String clubId,
  }) {
    return RunTrackViewModel._(repository, clubId);
  }

  RunTrackViewModel._(this._repository, this._clubId);

  final RunTrackRepository _repository;
  final String _clubId;

  TimeRange _selectedRange = TimeRange.today;
  TimeRange get selectedRange => _selectedRange;

  RunTrackFeedState? _state;
  RunTrackFeedState? get state => _state;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<ActivityFeedItem> _allActivities = [];

  void updateTimeRange(TimeRange newRange) {
    if (_selectedRange == newRange) return;
    _selectedRange = newRange;
    _filterActivities();
  }

  /// Clears the repository cache and reloads the activity feed.
  Future<void> refresh() async {
    // Cast to MockRunTrackRepository to access clearCache
    if (_repository is MockRunTrackRepository) {
      (_repository).clearCache();
    }

    await loadState();
  }

  Future<void> loadState() async {
    _isLoading = true;
    notifyListeners();

    _allActivities = await _repository.fetchActivities(_clubId);
    _isLoading = false;
    _filterActivities();
  }

  void _filterActivities() {
    // Filter activities based on the selected range
    final now = DateTime.now();
    final filteredActivities = _allActivities.where((activity) {
      // Safely parse the startDate
      final activityDate = DateTime.tryParse(activity.startDate) ?? now;

      switch (_selectedRange) {
        case TimeRange.today:
          return activityDate.year == now.year &&
              activityDate.month == now.month &&
              activityDate.day == now.day;
        case TimeRange.week:
          final difference = now.difference(activityDate).inDays;
          return difference >= 0 && difference < 7;
        case TimeRange.month:
          final difference = now.difference(activityDate).inDays;
          return difference >= 0 && difference < 30;
      }
    }).toList();

    _state = RunTrackFeedState(
      syncSummary: 'Synced Strava, Garmin and COROS mock webhooks on open',
      activities: filteredActivities,
    );

    notifyListeners();
  }
}

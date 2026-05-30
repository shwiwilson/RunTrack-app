import 'package:flutter/material.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';
export 'package:run_track_app/features/achievements/domain/models/achievements_models.dart';

class AchievementsViewModel extends ChangeNotifier {
  factory AchievementsViewModel({
    required RunTrackRepository repository,
    required String clubId,
  }) {
    return AchievementsViewModel._(repository, clubId);
  }

  AchievementsViewModel._(this._repository, this._clubId) {
    loadState();
  }

  final RunTrackRepository _repository;
  final String _clubId;

  AchievementsState? _state;
  AchievementsState? get state => _state;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadState() async {
    _isLoading = true;
    notifyListeners();

    _state = await _repository.fetchAchievements(_clubId);

    _isLoading = false;
    notifyListeners();
  }
}

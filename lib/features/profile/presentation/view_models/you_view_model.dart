import 'package:flutter/material.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/profile/domain/models/you_models.dart';
export 'package:run_track_app/features/profile/domain/models/you_models.dart';

class YouViewModel extends ChangeNotifier {
  factory YouViewModel({
    required RunTrackRepository repository,
    required String clubId,
    required String athleteId,
  }) {
    return YouViewModel._(repository, clubId, athleteId);
  }

  YouViewModel._(this._repository, this._clubId, this._athleteId) {
    loadState();
  }

  final RunTrackRepository _repository;
  final String _clubId;
  final String _athleteId;

  YouTabState? _state;
  YouTabState? get state => _state;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadState() async {
    _isLoading = true;
    notifyListeners();

    _state = await _repository.fetchReadiness(_clubId, _athleteId);

    _isLoading = false;
    notifyListeners();
  }
}

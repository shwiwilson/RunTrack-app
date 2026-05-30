import 'package:flutter/foundation.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
export 'package:run_track_app/features/club_hub/domain/models/club_models.dart';

class ClubHubViewModel extends ChangeNotifier {
  factory ClubHubViewModel({
    required RunTrackRepository repository,
    required String clubId,
    required String? athleteId,
  }) {
    return ClubHubViewModel._(repository, clubId, athleteId);
  }

  ClubHubViewModel._(this._repository, this._clubId, this._athleteId) {
    loadState();
  }

  final RunTrackRepository _repository;
  final String _clubId;
  final String? _athleteId;

  ClubHubState? _state;
  ClubHubState? get state => _state;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadState() async {
    _isLoading = true;
    notifyListeners();

    final sessions = await _repository.fetchClubSessions(_clubId);
    final staging = await _repository.fetchNewsletterStaging(_clubId);

    _state = ClubHubState(sessions: sessions, stagedItems: staging);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateRsvp(String sessionId, String status) async {
    if (_athleteId == null) return;
    await _repository.updateRsvp(sessionId, _athleteId, status);
    await loadState(); // Re-fetch data to reflect the changes in the UI
  }
}

import 'package:flutter/foundation.dart';
import 'package:run_track_app/core/platform/browser_location.dart';
import 'package:run_track_app/features/club_hub/domain/club_selection.dart';
import 'package:run_track_app/domain/run_track_snapshot.dart';
import 'package:run_track_app/features/club_hub/domain/repositories/run_track_repository.dart';

class RunTrackController extends ChangeNotifier {
  RunTrackController(this.repository);
  final RunTrackRepository repository;
  RunTrackSnapshot? snapshot;
  bool loading = true;
  bool saving = false;
  String? error;
  int selectedTab = 0;
  bool _disposed = false;

  void selectTab(int value) {
    selectedTab = value;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (saving) return;
    loading = true;
    error = null;
    _notify();
    try {
      snapshot = await repository.load(
        activeClubId: snapshot?.membership?.clubId,
      );
    } catch (_) {
      error =
          'Unable to load your RunTrack data. Check your connection and try again.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> switchClub(String clubId) async {
    final current = snapshot;
    if (loading ||
        saving ||
        current == null ||
        current.membership?.clubId == clubId ||
        !current.memberships.any(
          (membership) => membership.clubId == clubId && membership.isActive,
        )) {
      return;
    }
    loading = true;
    error = null;
    _notify();
    try {
      final updated = await repository.load(activeClubId: clubId);
      snapshot = updated;
      final selected = updated.membership;
      if (selected?.clubId == clubId) {
        await saveClubSelection(
          updated.profile.id,
          clubId,
          installedClubSlug(),
        );
      } else {
        error = 'This club is no longer available to your account.';
      }
    } catch (_) {
      error = 'Unable to switch clubs. Check your connection and try again.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> mutate(Future<void> Function() action) async {
    if (saving || loading) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await action();
      try {
        snapshot = await repository.load(
          activeClubId: snapshot?.membership?.clubId,
        );
      } catch (_) {
        error =
            'Your change was saved, but the updated data could not be loaded. Reload to see the latest records.';
      }
      return true;
    } catch (_) {
      error =
          'This change could not be saved. Check your connection and permissions, then retry.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

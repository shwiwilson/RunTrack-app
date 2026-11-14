import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_track_app/core/theme/club_branding.dart';
import 'package:run_track_app/features/club_hub/domain/club_selection.dart';
import 'package:run_track_app/features/club_hub/domain/models/club_models.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

ClubMembership membership(
  String id, {
  String status = 'active',
  String clubStatus = 'active',
  Map<String, dynamic> theme = const {},
}) => ClubMembership(
  id: 'membership-$id',
  clubId: id,
  userId: 'runner',
  role: 'admin',
  status: status,
  clubStatus: clubStatus,
  clubName: 'Club $id',
  installSlug: 'club-$id',
  theme: theme,
);

void main() {
  test(
    'selects only active memberships, with a valid preference or launch slug',
    () {
      final first = membership('one');
      final second = membership('two');
      final removed = membership('three', status: 'removed');
      final closed = membership('four', clubStatus: 'inactive');
      final clubs = [first, second, removed, closed];
      expect(ClubMembership.selectActive(clubs), first);
      expect(
        ClubMembership.selectActive(clubs, launchSlug: 'club-two'),
        second,
      );
      expect(
        ClubMembership.selectActive(
          clubs,
          preferredId: 'one',
          launchSlug: 'club-two',
        ),
        first,
      );
      expect(
        ClubMembership.selectActive(
          clubs,
          preferredId: 'three',
          launchSlug: 'club-four',
        ),
        first,
      );
      expect(ClubMembership.selectActive([removed, closed]), isNull);
      expect(clubInstallPath(second), '/club/club-two/install');
      expect(clubInstallPath(null), isNull);
    },
  );

  test('persists by runner and by installed club', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await saveClubSelection('one', 'club-two', 'club-one');
    expect(await readClubSelection('one', 'club-one'), 'club-two');
    expect(await readClubSelection('one', null), 'club-two');
    expect(await readClubSelection('one', 'club-three'), isNull);
    expect(await readClubSelection('two', 'club-one'), isNull);
  });

  test(
    'malformed theme data falls back and configured colours stay readable',
    () {
      final theme = clubBrandTheme(
        membership(
          'one',
          theme: {
            'colors': {
              'primary': '#EEEEEE',
              'secondary': '#AD46C1',
              'background': '#111111',
              'onPrimary': '#EEEEEE',
            },
          },
        ),
      );
      expect(theme.colorScheme.primary, const Color(0xffeeeeee));
      expect(theme.colorScheme.onPrimary, Colors.black);
      expect(theme.colorScheme.secondary, const Color(0xffad46c1));
      expect(theme.scaffoldBackgroundColor, const Color(0xff111111));
      expect(
        clubBrandTheme(
          membership('two', theme: {'colors': 'legacy'}),
        ).colorScheme.primary,
        const Color(0xff315a18),
      );
    },
  );
}

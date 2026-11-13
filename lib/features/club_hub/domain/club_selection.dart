import 'package:shared_preferences/shared_preferences.dart';

String _key(String userId, String? launchSlug) =>
    'runtrack.active-club.$userId.${launchSlug ?? 'default'}';

Future<String?> readClubSelection(String userId, String? launchSlug) async {
  try {
    return await SharedPreferencesAsync().getString(_key(userId, launchSlug));
  } on Exception {
    return null;
  }
}

Future<void> saveClubSelection(
  String userId,
  String clubId,
  String? launchSlug,
) async {
  try {
    final preferences = SharedPreferencesAsync();
    if (launchSlug != null) {
      await preferences.setString(_key(userId, launchSlug), clubId);
    }
    await preferences.setString(_key(userId, null), clubId);
  } on Exception {
    // Browsers may deny storage. The current shell can still switch clubs.
  }
}

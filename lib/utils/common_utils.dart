import 'package:run_track_app/core/extensions/extensions.dart';

class CommonUtils {
  static String joinAthleteNames(List<dynamic> athletes, String delimiter) {
    if (athletes.isEmpty) {
      return '';
    }

    final joined = athletes
        .map<String>((athlete) => athlete.toString().trim())
        .where((name) => name.isNotEmpty)
        .join(delimiter);

    if (joined.isEmpty) {
      return '';
    }

    return joined;
  }

  static bool isNumeric(String? value) {
    if (value == null) {
      return false;
    }

    return double.tryParse(value) != null;
  }

  static bool isEmail(String email) {
    if (email.isEmpty) {
      return false;
    }

    // Simple email regex pattern
    final emailPattern = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailPattern.hasMatch(email);
  }

  static String getInitials(String? name) {
    return name?.initials() ?? '';
  }

  static bool isEmpty(String? value) {
    // Consider null and empty string as empty
    // Single space is considered not empty
    if (value == null) {
      return true;
    }

    return value.isEmpty;
  }
}

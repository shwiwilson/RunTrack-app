// Standard utility location for the application

class CommonUtils {
  static String joinAthleteNames(List<String>? names) {
    if (names == null || names.isEmpty) return '';
    return names.join(' | ');
  }

  static String getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static bool isNumeric(String? s) {
    if (s == null || s.isEmpty) return false;
    return double.tryParse(s) != null;
  }

  static bool isEmpty(String? s) {
    return s == null || s.isEmpty;
  }
}

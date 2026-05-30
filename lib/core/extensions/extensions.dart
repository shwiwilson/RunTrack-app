extension StringExtensions on String {
  String initials() {
    final trimmed = trim();
    if (trimmed.isEmpty) return '';

    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    if (words.length == 1) return words.first[0].toUpperCase();

    return (words.first[0] + words.last[0]).toUpperCase();
  }
}

import 'package:web/web.dart' as web;

void clearAccountIntent() {
  final current = Uri.parse(web.window.location.href);
  final parameters = Map<String, String>.from(current.queryParameters)
    ..remove('flow')
    ..remove('health')
    ..remove('health_result');
  web.window.history.replaceState(
    null,
    '',
    current.replace(queryParameters: parameters).toString(),
  );
}

String? installedClubSlug() {
  final segments = Uri.base.pathSegments;
  final requested =
      segments.length == 3 && segments.first == 'club' && segments.last == 'app'
      ? segments[1]
      : null;
  try {
    final session = web.window.sessionStorage;
    if (requested != null && _isClubSlug(requested)) {
      session.setItem('runtrack.launch-club', requested);
      return requested;
    }
    final previous = session.getItem('runtrack.launch-club');
    return previous != null && _isClubSlug(previous) ? previous : null;
  } on Object {
    return requested != null && _isClubSlug(requested) ? requested : null;
  }
}

bool _isClubSlug(String value) =>
    value.length <= 80 && RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(value);

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

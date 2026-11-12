import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String> downloadExport(String contents) async {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'runtrack-personal-data.json';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Keep the URL alive long enough for Safari to begin the download.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return 'Your personal data export is downloading. Store it securely.';
}

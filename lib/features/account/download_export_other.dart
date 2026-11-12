import 'package:flutter/services.dart';

Future<String> downloadExport(String contents) async {
  await Clipboard.setData(ClipboardData(text: contents));
  return 'Your JSON export was copied. Paste it into a file to save it securely.';
}

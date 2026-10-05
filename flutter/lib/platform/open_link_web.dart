import 'package:web/web.dart' as web;

Future<bool> openLink(String url) async {
  web.window.open(url, '_blank', 'noopener');
  return true;
}

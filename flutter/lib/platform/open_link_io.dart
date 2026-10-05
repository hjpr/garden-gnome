import 'dart:io';

Future<bool> openLink(String url) async {
  final (command, args) = switch (Platform.operatingSystem) {
    'macos' => ('open', [url]),
    'windows' => ('cmd', ['/c', 'start', '', url]),
    _ => ('xdg-open', [url]),
  };
  try {
    final result = await Process.run(command, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

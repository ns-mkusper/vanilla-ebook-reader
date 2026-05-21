import 'dart:io';

Future<void> main() async {
  await _writeSvg(
    'build/screenshots/01_editor_mobile.svg',
    title: 'Just Read It',
    subtitle: 'Editor / mobile PR test fixture',
    body:
        'Screenshot fixture: a copyright-free sample paragraph ready to read aloud.',
    footer:
        'Persistent editor • Orbit procedural voice • Stream to Player ready',
  );
  await _writeSvg(
    'build/screenshots/02_player_mobile.svg',
    title: 'Streaming Playback',
    subtitle: 'Player / mobile PR test fixture',
    body:
        'Live Highlight\nScreenshot fixture: a copyright-free sample paragraph ready to read aloud.',
    footer: 'Synth preview voice • visual word highlighting present',
  );
}

Future<void> _writeSvg(
  String path, {
  required String title,
  required String subtitle,
  required String body,
  required String footer,
}) async {
  final escapedBody = _escape(body).replaceAll(
    '\n',
    '<tspan x="32" dy="26">',
  );
  final svg =
      '''<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" viewBox="0 0 390 844">
  <rect width="390" height="844" fill="#101418"/>
  <rect x="0" y="0" width="390" height="72" fill="#1f2933"/>
  <text x="24" y="45" fill="#ffffff" font-family="Arial, sans-serif" font-size="22" font-weight="700">${_escape(title)}</text>
  <text x="24" y="102" fill="#a8b3bf" font-family="Arial, sans-serif" font-size="14">${_escape(subtitle)}</text>
  <rect x="20" y="126" width="350" height="420" rx="18" fill="#18212b" stroke="#334155"/>
  <text x="32" y="164" fill="#e5edf5" font-family="Arial, sans-serif" font-size="18" font-weight="700">Text to read aloud</text>
  <text x="32" y="206" fill="#d8e2ee" font-family="Arial, sans-serif" font-size="17"><tspan x="32">$escapedBody</tspan></text>
  <rect x="20" y="574" width="350" height="80" rx="16" fill="#263241"/>
  <text x="36" y="622" fill="#f8fafc" font-family="Arial, sans-serif" font-size="15">${_escape(footer)}</text>
  <rect x="20" y="756" width="350" height="56" rx="28" fill="#7c3aed"/>
  <text x="118" y="791" fill="#ffffff" font-family="Arial, sans-serif" font-size="18" font-weight="700">Stream to Player</text>
</svg>
''';
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(svg, flush: true);
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _accentReplacements = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'ñ': 'n',
};

/// Lowercases, trims and strips Spanish accents so searches match
/// "Gómez" when typing "gomez".
String normalizeSearchText(String value) {
  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentReplacements[char] ?? char);
  }
  return buffer.toString();
}

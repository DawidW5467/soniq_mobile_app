/// Artist normalization helpers.
///
/// Goal: merge variations like:
///   "HEALTH" vs "HEALTH ft. Sierra" vs "HEALTH feat Sierra"
/// into the same library buckets.
///
/// This is intentionally conservative: it only strips common featuring patterns
/// and separators, and keeps the primary artist.
class ArtistNormalizer {
  ArtistNormalizer._();

  /// Returns a normalized *key* for grouping.
  ///
  /// Examples:
  /// - "HEALTH ft. Sierra" -> "health"
  /// - "HEALTH feat Sierra" -> "health"
  /// - "HEALTH & Sierra" -> "health"
  /// - "HEALTH x Sierra" -> "health"
  /// - "HEALTH, Sierra" -> "health"
  static String key(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';

    // Normalize whitespace.
    var x = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove parenthetical featuring suffixes: "(feat. X)", "(ft X)" etc.
    x = x.replaceAll(RegExp(r'\s*\((?:feat|featuring|ft)\.?\s+[^)]*\)\s*', caseSensitive: false), '');

    // Split on common featuring tokens.
    final featSplit = RegExp(r'\s+(?:feat|featuring|ft)\.?\s+', caseSensitive: false);
    final m = featSplit.firstMatch(x);
    if (m != null) {
      x = x.substring(0, m.start).trim();
    }

    // Split on separators that typically mean multiple artists where the first one
    // is the primary for album grouping.
    // IMPORTANT: don't split on '/' when it's part of the name (e.g. "AC/DC").
    // We only split on separators that are surrounded by spaces.
    // Examples: "A & B", "A x B", "A × B", "A / B", "A + B".
    // We also split on comma (",") as it's rarely part of an artist name.
    final parts = x
        .split(RegExp(r'\s*(?:,|\s+&\s+|\s+[xX]\s+|\s+×\s+|\s+/\s+|\s+\+\s+)\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      x = parts.first;
    }

    // Final compact.
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x.toLowerCase();
  }

  /// Returns a display name for the primary artist.
  /// If we can't parse, returns the trimmed raw.
  static String primaryDisplay(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final k = key(s);
    if (k.isEmpty) return s;
    // Preserve original casing of the primary part by re-parsing similarly.
    var x = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    x = x.replaceAll(RegExp(r'\s*\((?:feat|featuring|ft)\.?\s+[^)]*\)\s*', caseSensitive: false), '');
    final featSplit = RegExp(r'\s+(?:feat|featuring|ft)\.?\s+', caseSensitive: false);
    final m = featSplit.firstMatch(x);
    if (m != null) x = x.substring(0, m.start).trim();
    final parts = x
        .split(RegExp(r'\s*(?:,|\s+&\s+|\s+[xX]\s+|\s+×\s+|\s+/\s+|\s+\+\s+)\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.first : s;
  }
}

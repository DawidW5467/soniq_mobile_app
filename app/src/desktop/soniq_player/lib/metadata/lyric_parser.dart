class LyricLine {
  LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

class LyricParser {
  /// Parses standard LRC content:
  /// [mm:ss.xx] line text
  ///
  /// Returns a sorted list of LyricLines.
  static List<LyricLine> parse(String content) {
    if (content.trim().isEmpty) return [];

    final lines = content.split('\n');
    final result = <LyricLine>[];
    
    // Regex for [mm:ss.xx] or [mm:ss]
    final reg = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\]');

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Find all timestamps in the line (sometimes multiple timestamps for repeated lines)
      // e.g. [00:12.00][00:24.00]Same text
      final matches = reg.allMatches(line);
      if (matches.isEmpty) continue;

      // Extract text part (everything after the last bracket)
      final lastMatch = matches.last;
      String text = line.substring(lastMatch.end).trim();

      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final millisStr = m.group(3);
        int millis = 0;
        if (millisStr != null) {
          // .xx usually means hundredths, so 10 -> 100ms, 5 -> 500ms? 
          // Standard is usually hundredths.
          if (millisStr.length == 2) {
            millis = int.parse(millisStr) * 10;
          } else if (millisStr.length == 3) {
            millis = int.parse(millisStr);
          } else {
            // fallback
            millis = int.parse(millisStr);
          }
        }

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );

        result.add(LyricLine(time: duration, text: text));
      }
    }

    // Sort by time
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}


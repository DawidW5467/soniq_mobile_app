import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'libdiscid_ffi.dart';

/// Rezultat wyszukiwania metadanych płyty CD.
class CdTrackMetadata {
  final String title;
  final String? artist;
  final String? album;
  final int trackNumber;
  final Duration? length;
  CdTrackMetadata({
    required this.title,
    required this.trackNumber,
    this.artist,
    this.album,
    this.length,
  });
}

/// Prosta klasa do pobierania nazw utworów z MusicBrainz.
/// W przypadku braku dopasowania generuje nazwy zastępcze "Track 01" itd.
class CdMetadataFetcher {
  /// Pobierz metadane; używa heurystyk (liczba utworów, nazwa katalogu) i kilku zapytań MB.
  static Future<List<CdTrackMetadata>> fetch({
    required Directory cdDirectory,
    String? hintTitle, // np. nazwa folderu (album/artysta)
  }) async {
    final files = cdDirectory
        .listSync()
        .whereType<File>()
        .where((f) => _isAudio(f.path))
        .toList();
    final trackCount = files.length;
    if (trackCount == 0) return [];

    // 0) Spróbuj obliczyć MusicBrainz Disc ID i pobrać precyzyjne metadane
    final discId = await _computeDiscId();
    if (discId != null && discId.isNotEmpty) {
      final byDiscid = await _fetchByDiscId(discId);
      if (byDiscid != null && byDiscid.isNotEmpty) {
        return byDiscid;
      }
    }

    // Heurystyka: nazwa katalogu jako podpowiedź
    hintTitle ??= p.basename(cdDirectory.path);
    hintTitle = _sanitizeQuery(hintTitle);

    // 1) Spróbuj dopasować dokładny release po liczbie utworów + format:CD + nazwa (jeśli dostępna)
    final strategies = <Uri>[
      _buildReleaseQuery(trackCount: trackCount, hint: hintTitle, formatCd: true),
      _buildReleaseQuery(trackCount: trackCount, hint: hintTitle, formatCd: false),
      _buildReleaseGroupQuery(hint: hintTitle),
      Uri.parse('https://musicbrainz.org/ws/2/release/?query=tracks:$trackCount AND status:official&fmt=json'),
    ];

    for (final uri in strategies) {
      final tracks = await _tryFetchFromMusicBrainz(uri, trackCount);
      if (tracks != null && tracks.isNotEmpty) {
        return tracks;
      }
    }

    // 2) Fallback: spróbuj odczytać sensowne tytuły z nazw plików.
    final filenameDerived = files.asMap().entries.map((e) {
      final tn = e.key + 1;
      final name = _titleFromFilename(p.basename(e.value.path));
      return CdTrackMetadata(
        title: name.isNotEmpty ? name : 'Track ${tn.toString().padLeft(2, '0')}',
        trackNumber: tn,
      );
    }).toList();
    if (filenameDerived.any((t) => t.title.isNotEmpty)) {
      return filenameDerived;
    }

    // 3) Ostateczny fallback: Track 01, Track 02, ...
    return List.generate(trackCount, (i) {
      final tn = i + 1;
      return CdTrackMetadata(
        title: 'Track ${tn.toString().padLeft(2, '0')}',
        trackNumber: tn,
      );
    });
  }

  static Uri _buildReleaseQuery({required int trackCount, String? hint, bool formatCd = true}) {
    final base = 'https://musicbrainz.org/ws/2/release/';
    final queryParts = <String>['status:official', 'tracks:$trackCount'];
    if (formatCd) queryParts.add('format:CD');
    if (hint != null && hint.trim().isNotEmpty) {
      queryParts.add('(${hint.trim()})');
    }
    final q = queryParts.join(' AND ');
    return Uri.parse('$base?query=$q&fmt=json');
  }

  static Uri _buildReleaseGroupQuery({String? hint}) {
    final base = 'https://musicbrainz.org/ws/2/release-group/';
    final query = hint != null && hint.trim().isNotEmpty ? hint.trim() : '';
    return Uri.parse('$base?query=$query&fmt=json');
  }

  static Future<List<CdTrackMetadata>?> _tryFetchFromMusicBrainz(Uri uri, int expectedCount) async {
    try {
      final resp = await http.get(uri, headers: {
        'User-Agent': 'SoniqPlayer/1.0 (linux)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final releases = (data['releases'] as List?) ?? (data['release-groups'] as List?) ?? [];
      if (releases.isEmpty) return null;

      // Przejdź po release, wybierz ten z medium zawierającym ścieżki.
      Map<String, dynamic>? selected;
      for (final r0 in releases) {
        final r = r0 is Map ? Map<String, dynamic>.from(r0) : null;
        if (r == null) continue;
        final media = r['media'];
        if (media is List && media.isNotEmpty) {
          final firstMedium = media.first;
          final tracks = (firstMedium is Map && firstMedium['tracks'] is List)
              ? (firstMedium['tracks'] as List)
              : [];
          if (tracks.isNotEmpty) {
            selected = r;
            // Preferuj dokładny count jeśli pasuje
            if (tracks.length == expectedCount) break;
          }
        }
      }
      selected ??= (releases.first is Map)
          ? Map<String, dynamic>.from(releases.first as Map)
          : null;
      if (selected == null) return null;

      final media = selected['media'] as List?;
      if (media == null || media.isEmpty) return null;
      final firstMedium = media.first as Map<String, dynamic>;
      final tracks = (firstMedium['tracks'] as List?) ?? [];
      if (tracks.isEmpty) return null;

      final album = selected['title'] as String?;
      String? artist;
      final artistCredit = selected['artist-credit'];
      if (artistCredit is List && artistCredit.isNotEmpty) {
        final first = artistCredit.first;
        if (first is Map && first['name'] is String) {
          artist = first['name'] as String?;
        }
      }

      // Zmapuj ścieżki – dopasuj po numerze, a jeśli brak, użyj kolejności.
      final out = <CdTrackMetadata>[];
      for (var i = 0; i < tracks.length; i++) {
        final t = tracks[i] as Map<String, dynamic>;
        final numberStr = (t['number'] as String?) ?? '';
        final number = int.tryParse(numberStr);
        final tn = number ?? (i + 1);
        String title = (t['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) {
          title = 'Track ${tn.toString().padLeft(2, '0')}';
        }
        Duration? length;
        final len = t['length'];
        if (len is int) {
          length = Duration(milliseconds: len);
        } else if (len is String) {
          final parsed = int.tryParse(len);
          if (parsed != null) length = Duration(milliseconds: parsed);
        }
        out.add(CdTrackMetadata(
          title: title,
          trackNumber: tn,
          artist: artist,
          album: album,
          length: length,
        ));
      }

      // Jeśli liczba nie pasuje, wciąż zwróć (lepsze niż brak), a UI może dopasować po tn.
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Spróbuj obliczyć MusicBrainz Disc ID korzystając z narzędzi systemowych.
  /// Preferowane: `cd-discid`. Fallback: parsowanie `cdparanoia -Q`.
  static Future<String?> _computeDiscId() async {
    // Tylko FFI libdiscid – bez cd-discid
    final lib = LibDiscid.load();
    if (lib != null) {
      final id = lib.computeDiscId();
      if (id != null && id.isNotEmpty) {
        print('libdiscid Disc ID: $id');
        return id;
      }
    }

    // Opcjonalny fallback: odczyt TOC przez cdparanoia -Q (bez obliczania Disc ID)
    try {
      final res = await Process.run('cdparanoia', ['-Q']);
      if (res.exitCode == 0) {
        final out = (res.stdout as String).toString();
        final lines = out.split('\n');
        final offsets = <int>[];
        for (final line in lines) {
          final m = RegExp(r'^\s*\d+\.\s*(\d+):(\d+)\.(\d+)\s*\[\s*(\d+)\s*\]').firstMatch(line.trim());
          if (m != null) {
            final sectors = int.tryParse(m.group(4)!);
            if (sectors != null) offsets.add(sectors);
          }
        }
        if (offsets.isNotEmpty) {
          print('cdparanoia TOC offsets: ${offsets.length} tracks');
        }
      }
    } catch (_) {}

    return null;
  }

  /// Pobierz metadane z MusicBrainz używając endpointu Disc ID.
  static Future<List<CdTrackMetadata>?> _fetchByDiscId(String discId) async {
    try {
      final uri = Uri.parse('https://musicbrainz.org/ws/2/discid/$discId?inc=recordings+artists&fmt=json');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'SoniqPlayer/1.0 (linux)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final releases = data['releases'] as List?;
      if (releases == null || releases.isEmpty) return null;
      // Wybierz pierwsze release z tracklistą
      for (final r0 in releases) {
        if (r0 is Map<String, dynamic>) {
          final media = r0['media'] as List?;
          if (media == null || media.isEmpty) continue;
          final firstMedium = media.first as Map<String, dynamic>;
          final tracks = firstMedium['tracks'] as List?;
          if (tracks == null || tracks.isEmpty) continue;
          final album = r0['title'] as String?;
          String? artist;
          final artistCredit = r0['artist-credit'];
          if (artistCredit is List && artistCredit.isNotEmpty) {
            final first = artistCredit.first;
            if (first is Map && first['name'] is String) {
              artist = first['name'] as String?;
            }
          }
          final out = <CdTrackMetadata>[];
          for (var i = 0; i < tracks.length; i++) {
            final t = tracks[i] as Map<String, dynamic>;
            final rec = t['recording'] as Map<String, dynamic>?;
            String title = (rec?['title'] as String?)?.trim() ?? (t['title'] as String?)?.trim() ?? '';
            final numberStr = (t['number'] as String?) ?? '';
            final number = int.tryParse(numberStr) ?? (i + 1);
            Duration? length;
            final len = rec?['length'] ?? t['length'];
            if (len is int) {
              length = Duration(milliseconds: len);
            } else if (len is String) {
              final parsed = int.tryParse(len);
              if (parsed != null) length = Duration(milliseconds: parsed);
            }
            if (title.isEmpty) {
              title = 'Track ${number.toString().padLeft(2, '0')}';
            }
            out.add(CdTrackMetadata(
              title: title,
              trackNumber: number,
              artist: artist,
              album: album,
              length: length,
            ));
          }
          return out;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeQuery(String? s) {
    if (s == null) return '';
    var out = s.replaceAll(RegExp(r'[_\-]+'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static String _titleFromFilename(String filename) {
    var name = filename;
    // Usuń rozszerzenie
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    // Usuń prefiksy numeryczne typu "01 - ", "01.", "1_"
    name = name.replaceFirst(RegExp(r'^(\d{1,2})[\s_.-]+'), '');
    // Podmień podkreślenia na spacje
    name = name.replaceAll('_', ' ').replaceAll('-', ' ');
    // Usuń nadmiarowe spacje
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  static bool _isAudio(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.wav' || ext == '.flac' || ext == '.mp3' || ext == '.ogg';
  }
}

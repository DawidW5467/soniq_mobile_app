import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import 'library_models.dart';
import '../metadata/artist_normalizer.dart';

class LibraryController {
  LibraryController._();
  static final LibraryController instance = LibraryController._();

  final AudioController _audio = AudioController();

  final ValueNotifier<LibraryIndex> index = ValueNotifier<LibraryIndex>(LibraryIndex.empty());
  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(false);

  Timer? _debounce;
  Future<void>? _running;

  static const _allowedExt = {'.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'};

  void scheduleRebuild(Map<String, String> sources, {Duration debounce = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      if (_running != null) return;
      _running = _rebuildInternal(sources).whenComplete(() => _running = null);
    });
  }

  Future<void> rebuild({required Map<String, String> sources}) async {
    if (_running != null) return;
    _running = _rebuildInternal(sources).whenComplete(() => _running = null);
    await _running;
  }

  Future<void> _rebuildInternal(Map<String, String> sources) async {
    isIndexing.value = true;
    try {
      final tracks = <LibraryTrack>[];
      for (final entry in sources.entries) {
        final sourceName = entry.key;
        final sourcePath = entry.value;
        if (sourcePath.trim().isEmpty) continue;

        // CDDA pomijamy w globalnym indeksie (zwykle wolne i zmienne)
        final isCdda = sourcePath.contains('cdda') || sourcePath.contains('gvfs/cdda');
        if (isCdda) continue;

        final dir = Directory(sourcePath);
        if (!await dir.exists()) continue;

        // 1 poziom – kioskowo przewidywalnie i szybko.
        final entities = await dir.list(followLinks: false).toList();
        for (final e in entities) {
          if (e is! File) continue;
          final ext = p.extension(e.path).toLowerCase();
          if (!_allowedExt.contains(ext)) continue;

          final meta = await _audio.getMetadata(e.path);
          tracks.add(
            LibraryTrack(
              path: e.path,
              sourceName: sourceName,
              sourcePath: sourcePath,
              meta: meta,
            ),
          );
        }
      }

      // Sort utworów: artysta/album/trackNumber/tytuł
      tracks.sort((a, b) {
        int c = a.artistOrUnknown.toLowerCase().compareTo(b.artistOrUnknown.toLowerCase());
        if (c != 0) return c;
        c = a.albumOrUnknown.toLowerCase().compareTo(b.albumOrUnknown.toLowerCase());
        if (c != 0) return c;
        final an = a.meta.trackNumber ?? 9999;
        final bn = b.meta.trackNumber ?? 9999;
        if (an != bn) return an.compareTo(bn);
        return a.titleOrFileName.toLowerCase().compareTo(b.titleOrFileName.toLowerCase());
      });

      final albumMap = <String, List<LibraryTrack>>{};
      final artistMap = <String, List<LibraryTrack>>{};
      final artistDisplayByKey = <String, String>{};

      for (final t in tracks) {
        final rawArtist = t.artistOrUnknown;
        final artistKey = ArtistNormalizer.key(rawArtist);
        final artistDisplay = ArtistNormalizer.primaryDisplay(rawArtist);

        // jeśli nie udało się znormalizować, fallback do raw
        final effectiveKey = artistKey.isNotEmpty ? artistKey : rawArtist.toLowerCase();
        artistDisplayByKey.putIfAbsent(effectiveKey, () => artistDisplay.isNotEmpty ? artistDisplay : rawArtist);

        final albumKey = '${t.albumOrUnknown}@@$effectiveKey';
        albumMap.putIfAbsent(albumKey, () => []).add(t);
        artistMap.putIfAbsent(effectiveKey, () => []).add(t);
      }

      final albums = albumMap.entries.map((e) {
        final parts = e.key.split('@@');
        final albumName = parts.first;
        final artistKey = parts.length > 1 ? parts[1] : 'nieznany';
        final artistName = artistDisplayByKey[artistKey] ?? 'Unknown artist';
        final list = e.value;
        list.sort((a, b) {
          final an = a.meta.trackNumber ?? 9999;
          final bn = b.meta.trackNumber ?? 9999;
          if (an != bn) return an.compareTo(bn);
          return a.titleOrFileName.toLowerCase().compareTo(b.titleOrFileName.toLowerCase());
        });
        return LibraryAlbum(name: albumName, artistKey: artistName, tracks: list);
      }).toList();

      albums.sort((a, b) {
        int c = a.artistKey.toLowerCase().compareTo(b.artistKey.toLowerCase());
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      final artists = artistMap.entries.map((e) {
        final list = e.value;
        final name = artistDisplayByKey[e.key] ?? e.key;
        return LibraryArtist(name: name, tracks: list);
      }).toList();

      artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      index.value = LibraryIndex(
        tracks: List.unmodifiable(tracks),
        albums: List.unmodifiable(albums),
        artists: List.unmodifiable(artists),
        updatedAt: DateTime.now(),
      );
    } catch (e, st) {
      debugPrint('LibraryController.rebuild error: $e\n$st');
    } finally {
      isIndexing.value = false;
    }
  }

  void dispose() {
    _debounce?.cancel();
    index.dispose();
    isIndexing.dispose();
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'playlist_models.dart';

/// Przechowywanie playlist w lokalnym pliku JSON.
///
/// Uwaga: na desktop Linux trzymamy plik w katalogu roboczym aplikacji
/// jako fallback. Jeśli chcesz docelową ścieżkę (XDG), możemy później
/// podpiąć path_provider.
class PlaylistStorage {
  PlaylistStorage({String fileName = 'soniq_playlists.json'}) : _fileName = fileName;

  final String _fileName;

  Future<File> _file() async {
    final dir = Directory.current;
    return File('${dir.path}/$_fileName');
  }

  Future<PlaylistsFile> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return PlaylistsFile.empty();
      final txt = await file.readAsString();
      return PlaylistsFile.decode(txt);
    } catch (e, st) {
      debugPrint('PlaylistStorage.load() error: $e\n$st');
      // Jeśli plik jest uszkodzony, nie wywalamy aplikacji.
      return PlaylistsFile.empty();
    }
  }

  Future<void> save(PlaylistsFile data) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');

    try {
      final content = data.encodePretty();
      await tmp.writeAsString(content, flush: true);

      if (await file.exists()) {
        // best-effort backup
        try {
          await file.copy(bak.path);
        } catch (_) {}
      }

      // Atomowy rename w obrębie FS.
      await tmp.rename(file.path);
    } catch (e, st) {
      debugPrint('PlaylistStorage.save() error: $e\n$st');
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }
}


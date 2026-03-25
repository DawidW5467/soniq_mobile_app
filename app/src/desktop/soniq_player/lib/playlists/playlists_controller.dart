import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio_controller.dart';
import 'playlist_models.dart';
import 'playlist_storage.dart';

enum PlaylistSortKey { addedAt, fileName, title, artist, album }
enum SortDirection { asc, desc }

class PlaylistsController extends ChangeNotifier {
  PlaylistsController._(this._storage);

  static final PlaylistsController instance = PlaylistsController._(PlaylistStorage());

  final PlaylistStorage _storage;
  final AudioController _audio = AudioController();

  bool _loaded = false;
  final List<Playlist> _playlists = [];

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final file = await _storage.load();
    _playlists
      ..clear()
      ..addAll(file.playlists.where((p) => p.id.isNotEmpty));
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final file = PlaylistsFile(schemaVersion: 1, playlists: _playlists);
    await _storage.save(file);
  }

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return '$now-$r';
  }

  Future<String> createPlaylist(String name) async {
    await ensureLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pl = Playlist(
      id: _newId(),
      name: name.trim().isEmpty ? 'Playlista' : name.trim(),
      items: [],
      createdAtEpochMs: now,
      updatedAtEpochMs: now,
    );
    _playlists.insert(0, pl);
    await _persist();
    notifyListeners();
    return pl.id;
  }

  Future<void> renamePlaylist({required String playlistId, required String name}) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _playlists[idx] = _playlists[idx].copyWith(name: name.trim(), updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await ensureLoaded();
    _playlists.removeWhere((p) => p.id == playlistId);
    await _persist();
    notifyListeners();
  }

  Playlist? getById(String id) {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx < 0) return null;
    return _playlists[idx];
  }

  Future<void> addTrack({required String playlistId, required String path}) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    final items = [..._playlists[idx].items, PlaylistItem(
          id: _newId(),
          path: path,
          addedAtEpochMs: now,
        )]
      ;

    _playlists[idx] = _playlists[idx].copyWith(items: items, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  Future<void> addTracks({required String playlistId, required List<String> paths}) async {
    await ensureLoaded();
    if (paths.isEmpty) return;
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    final items = [..._playlists[idx].items];
    for (final path in paths) {
      items.add(
        PlaylistItem(
          id: _newId(),
          path: path,
          addedAtEpochMs: now,
        ),
      );
    }

    _playlists[idx] = _playlists[idx].copyWith(items: items, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  Future<void> removeItem({required String playlistId, required String itemId}) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = _playlists[idx].items.where((it) => it.id != itemId).toList();
    _playlists[idx] = _playlists[idx].copyWith(items: items, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  Future<void> moveItem({required String playlistId, required int oldIndex, required int newIndex}) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final items = [..._playlists[idx].items];
    if (oldIndex < 0 || oldIndex >= items.length) return;

    var target = newIndex;
    if (target > items.length) target = items.length;
    if (target < 0) target = 0;
    if (target > oldIndex) target -= 1;

    final item = items.removeAt(oldIndex);
    items.insert(target, item);

    final now = DateTime.now().millisecondsSinceEpoch;
    _playlists[idx] = _playlists[idx].copyWith(items: items, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  /// Widok sortowany bez zmiany kolejności zapisanej.
  Future<List<PlaylistItem>> getSortedView({
    required String playlistId,
    required PlaylistSortKey key,
    required SortDirection direction,
  }) async {
    await ensureLoaded();
    final pl = getById(playlistId);
    if (pl == null) return const [];

    final items = [...pl.items];
    final metaCache = <String, AudioMetadata>{};

    Future<AudioMetadata> meta(String path) async {
      final cached = metaCache[path];
      if (cached != null) return cached;
      final m = await _audio.getMetadata(path);
      metaCache[path] = m;
      return m;
    }

    int cmpStr(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

    Future<int> compare(PlaylistItem a, PlaylistItem b) async {
      switch (key) {
        case PlaylistSortKey.addedAt:
          return a.addedAtEpochMs.compareTo(b.addedAtEpochMs);
        case PlaylistSortKey.fileName:
          return cmpStr(_fileName(a.path), _fileName(b.path));
        case PlaylistSortKey.title:
          final ma = await meta(a.path);
          final mb = await meta(b.path);
          return cmpStr(ma.title ?? _fileName(a.path), mb.title ?? _fileName(b.path));
        case PlaylistSortKey.artist:
          final ma = await meta(a.path);
          final mb = await meta(b.path);
          return cmpStr(ma.artist ?? '', mb.artist ?? '');
        case PlaylistSortKey.album:
          final ma = await meta(a.path);
          final mb = await meta(b.path);
          return cmpStr(ma.album ?? '', mb.album ?? '');
      }
    }

    // sort async: zrobimy prostą wersję O(n^2) dla krótkich playlist.
    // Jeśli będziesz mieć tysiące pozycji, przerobimy to na prefetch + sort sync.
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final c = await compare(items[i], items[j]);
        final res = direction == SortDirection.asc ? c : -c;
        if (res > 0) {
          final tmp = items[i];
          items[i] = items[j];
          items[j] = tmp;
        }
      }
    }

    return items;
  }

  /// Zastosuj sortowanie (modyfikuje kolejność zapisanej playlisty).
  Future<void> applySort({
    required String playlistId,
    required PlaylistSortKey key,
    required SortDirection direction,
  }) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final sorted = await getSortedView(playlistId: playlistId, key: key, direction: direction);
    final now = DateTime.now().millisecondsSinceEpoch;
    _playlists[idx] = _playlists[idx].copyWith(items: sorted, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  /// Opcjonalna deduplikacja na żądanie (usuwa duplikaty po [path], zostawia pierwsze wystąpienie).
  Future<void> dedupeByPath({required String playlistId}) async {
    await ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;

    final seen = <String>{};
    final out = <PlaylistItem>[];
    for (final it in _playlists[idx].items) {
      if (seen.add(it.path)) out.add(it);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _playlists[idx] = _playlists[idx].copyWith(items: out, updatedAtEpochMs: now);
    await _persist();
    notifyListeners();
  }

  String _fileName(String path) {
    final sep = path.lastIndexOf('/');
    return sep >= 0 ? path.substring(sep + 1) : path;
  }
}


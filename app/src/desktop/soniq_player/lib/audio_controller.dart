import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_tags/dart_tags.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'metadata/cd_metadata.dart';
import 'metadata/metadata_cache_store.dart';

/// Minimalny model metadanych utworu
class AudioMetadata {
  const AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.coverBytes,
    this.coverMime,
    this.coverPath,
    this.lyrics,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final Uint8List? coverBytes;
  final String? coverMime;
  final String? coverPath;
  final String? lyrics; // Synced (LRC) or unsynced
}

/// Tryby zapętlenia używane przez UI i zdalne sterowanie.
enum LoopMode { off, all, one }

/// Udostępnia strumień stanu, który można łatwo obserwować z UI.
/// Singleton - jedna instancja współdzielona w całej aplikacji.
class AudioController {
  // Singleton pattern
  static final AudioController _instance = AudioController._internal();
  factory AudioController() => _instance;

  AudioController._internal() : _assetPath = 'assets/music.flac' {
    try {
      _player.setVolume(_lastVolume);
    } catch (e) {
      debugPrint('Nie udało się skonfigurować dodatkowych ustawień playera: $e');
    }
  }

  bool _looksSyncedLyrics(String text) {
    return RegExp(r'\[\d{1,2}:\d{2}([.:]\d{2,3})?\]').hasMatch(text);
  }

  final String _assetPath;
  final AudioPlayer _player = AudioPlayer();

  // Playlista lokalnych ścieżek (opcjonalna, gdy użytkownik wybierze katalog)
  List<String> _playlist = [];
  int _currentIndex = 0;
  List<int> _playOrder = [];
  int _playOrderIndex = 0;
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  String? _currentSourcePath;
  bool _assetLoaded = false;
  bool _isCddaPlaylist = false;
  DateTime? _suppressCompletionUntil;
  DateTime? _ignoreCompletionsUntil;
  double _lastVolume = 1.0;

  // Cache metadanych, aby nie czytać z pliku za każdym razem.
  final Map<String, AudioMetadata> _metadataCache = {};
  final Map<String, int> _metadataMtimeCache = {};

  // Strumień publicznego stanu dla UI.
  final ValueNotifier<AudioState> state =
      ValueNotifier<AudioState>(AudioState.initial());

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;
  final StreamController<int?> _indexController = StreamController<int?>.broadcast();

  int? _lastHandledIndex;

  bool _initialized = false;

  // Publiczny getter dla sprawdzenia stanu inicjalizacji
  bool get isInitialized => _initialized;
  bool get isCddaPlaylist => _isCddaPlaylist;

  // Flag: true when playing from a user-created playlist (not from directory source)
  bool _isPlaylistMode = false;

  bool get isPlaylistMode => _isPlaylistMode;

  /// Resetuje tryb playlisty — umożliwia załadowanie nowej playlisty z katalogu.
  void resetPlaylistMode() {
    _isPlaylistMode = false;
  }

  static const String _prefsLikedTracks = 'likedTracks';
  bool _likedLoaded = false;
  final Set<String> _likedPaths = <String>{};
  final ValueNotifier<Set<String>> likedPaths = ValueNotifier(<String>{});

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _loadLikedTracks();
      await _applyReleaseMode();

      _playerStateSub = _player.onPlayerStateChanged.listen((playerState) async {
        final isPlaying = playerState == PlayerState.playing;
        if (isPlaying) {
          await _applyVolumeAfterStart();
        }
        _updateState(isPlaying: isPlaying);
      });

      _durationSub = _player.onDurationChanged.listen((duration) {
        _updateState(duration: duration);
      });

      _positionSub = _player.onPositionChanged.listen((position) {
        _updateState(position: position);
      });

      _completeSub = _player.onPlayerComplete.listen((_) async {
        await _handleCompletion();
      });
    } catch (e, st) {
      debugPrint('Błąd inicjalizacji AudioController/audioplayers: $e\n$st');
    }
  }

  // Załaduj playlistę z listy lokalnych ścieżek (np. z MusicDirectoryManager)
  // Jeśli fromUserPlaylist=true, blokuje auto-refresh z innych źródeł
  Future<void> loadPlaylist(List<String> paths, {int startIndex = 0, bool fromUserPlaylist = false}) async {
    if (paths.isEmpty) return;

    // Jeśli gramy z playlisty użytkownika i ktoś próbuje załadować inną playlistę
    // bez flagi fromUserPlaylist - zignoruj (to auto-refresh z katalogu)
    if (_isPlaylistMode && !fromUserPlaylist && state.value.isPlaying) {
      return;
    }

    _isPlaylistMode = fromUserPlaylist;

    if (_isSamePlaylist(paths)) {
      _currentIndex = startIndex.clamp(0, _playlist.length - 1);
      _rebuildPlayOrder();
      await _handleIndexChange(_currentIndex, source: 'loadPlaylist');
      _indexController.add(_currentIndex);
      return;
    }
    _playlist = paths;
    _currentIndex = startIndex.clamp(0, _playlist.length - 1);
    _currentSourcePath = null;
    _lastHandledIndex = null;
    _rebuildPlayOrder();

    _metadataCache.removeWhere((key, _) => !_playlist.contains(key));
    _metadataMtimeCache.removeWhere((key, _) => !_playlist.contains(key));

    final firstPath = _playlist.first;
    _isCddaPlaylist = firstPath.contains('cdda') || firstPath.contains('gvfs/cdda');

    // Jeśli to CD – spróbuj pobrać listę nazw utworów
    if (_isCddaPlaylist) {
      _metadataCache.clear();
      _metadataMtimeCache.clear();
      _sortPlaylistForCd();

      final dir = Directory(firstPath).parent; // cdda ścieżki mogą być reprezentowane inaczej; uproszczenie
      if (await dir.exists()) {
        final tracksMeta = await CdMetadataFetcher.fetch(cdDirectory: dir);
        if (tracksMeta.length == _playlist.length) {
          for (var i = 0; i < _playlist.length; i++) {
            final path = _playlist[i];
            final trackNo = _parseCdTrackNumber(path);
            final meta = (trackNo != null && trackNo >= 1 && trackNo <= tracksMeta.length)
                ? tracksMeta[trackNo - 1]
                : tracksMeta[i];
            _metadataCache[path] = AudioMetadata(
              title: meta.title,
              artist: meta.artist,
              album: meta.album,
              trackNumber: trackNo ?? (i + 1),
            );
          }
        }
      }
    }

    await _handleIndexChange(_currentIndex, source: 'loadPlaylist');
    _indexController.add(_currentIndex);

    // Po załadowaniu zresetuj stan pozycji/długości (odczyt przyjdzie ze streamów)
    state.value = state.value.copyWith(position: Duration.zero);

    // Uruchom precaching w tle (pomijamy CD ze względu na koszt IO)
    _precacheMetadata();
  }

  int get currentIndex => _currentIndex;
  List<String> get playlist => List.unmodifiable(_playlist);

  /// Udostępnij metadane z cache dla UI.
  AudioMetadata? metadataForPath(String path) => _metadataCache[path];

  /// Publiczny async getter metadanych (z cache lub z dysku).
  /// UI może go używać np. w FutureBuilder.
  Future<AudioMetadata> getMetadata(String path, {bool forceRefresh = false}) =>
      _readMetadata(path, forceRefresh: forceRefresh);

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    final nextIndex = _getNextIndex();
    if (nextIndex == null) {
      await stop();
      return;
    }
    await _playIndex(nextIndex, suppressCompletion: true);
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    if (state.value.position >= const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    final prevIndex = _getPreviousIndex();
    if (prevIndex == null) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    await _playIndex(prevIndex, suppressCompletion: true);
  }

  // Historia odtwarzania (kiosk: przewidywalny przycisk "wstecz")
  static const int _historyMax = 200;
  final List<String> _history = <String>[];

  List<String> get history => List.unmodifiable(_history);

  void clearHistory() {
    _history.clear();
  }

  Future<void> back() async {
    if (_history.length < 2) {
      await previous();
      return;
    }

    // Ostatni element to aktualny utwór, więc cofamy się o 2.
    final targetPath = _history[_history.length - 2];
    final idx = _playlist.indexOf(targetPath);
    if (idx >= 0) {
      // Usuń bieżący wpis, żeby kolejne back działało sensownie.
      _history.removeLast();
      await _playIndex(idx, suppressCompletion: true);
    } else {
      // Jeśli utworu nie ma w playliście, fallback.
      await previous();
    }
  }

  void _pushHistoryForIndex(int idx) {
    if (_playlist.isEmpty) return;
    if (idx < 0 || idx >= _playlist.length) return;

    final path = _playlist[idx];
    if (_history.isNotEmpty && _history.last == path) return;

    _history.add(path);
    if (_history.length > _historyMax) {
      _history.removeRange(0, _history.length - _historyMax);
    }
  }

  Future<void> _handleIndexChange(int idx, {required String source}) async {
    if (_lastHandledIndex == idx) return;
    _lastHandledIndex = idx;
    _currentIndex = idx;
    _syncPlayOrderIndex();
    _indexController.add(idx);

    _pushHistoryForIndex(idx);

    if (_playlist.isNotEmpty && idx >= 0 && idx < _playlist.length) {
      final path = _playlist[idx];
      final meta = await _readMetadata(path);
      _updateState(
        currentTitle: meta.title,
        artist: meta.artist,
        album: meta.album,
        trackNumber: meta.trackNumber,
        currentIndex: idx,
        applyMetadata: true,
      );
      _debugPrintMetadata(source: source, path: path, meta: meta, index: idx);
    } else {
      _updateState(
        currentTitle: null,
        artist: null,
        album: null,
        trackNumber: null,
        currentIndex: idx,
        applyMetadata: true,
      );
    }
  }

  void _debugPrintMetadata({required String source, required String path, required AudioMetadata meta, required int index}) {
    debugPrint('[AudioController][$source] index=$index path=$path title=${meta.title} artist=${meta.artist} album=${meta.album} track=${meta.trackNumber}');
  }

  Future<void> _handleCompletion() async {
    final now = DateTime.now();

    if (_ignoreCompletionsUntil != null && now.isBefore(_ignoreCompletionsUntil!)) {
      return;
    }

    if (_suppressCompletionUntil != null && now.isBefore(_suppressCompletionUntil!)) {
      return;
    }
    if (_playlist.isEmpty) {
      _updateState(isPlaying: false, position: Duration.zero);
      return;
    }

    if (_loopMode == LoopMode.one) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }

    final nextIndex = _getNextIndex();
    if (nextIndex == null) {
      // End of playlist: stop completely.
      _ignoreCompletionsUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      _currentSourcePath = null;
      await clearPlaylist(stopPlayback: true);
      return;
    }

    await _playIndex(nextIndex, suppressCompletion: false);
  }

  Future<void> _playIndex(int index, {required bool suppressCompletion}) async {
    if (_playlist.isEmpty) return;
    if (suppressCompletion) {
      _suppressCompletionUntil = DateTime.now().add(const Duration(milliseconds: 500));
    }
    final clamped = index.clamp(0, _playlist.length - 1);
    final path = _playlist[clamped];
    final isNewTrack = _currentSourcePath != path;

    _currentIndex = clamped;
    _syncPlayOrderIndex();
    await _handleIndexChange(clamped, source: 'playIndex');

    if (isNewTrack || _player.state == PlayerState.stopped) {
      await _player.play(DeviceFileSource(path));
      _currentSourcePath = path;
      await _applyVolumeAfterStart();
      _updateState(isPlaying: true, position: Duration.zero);
    } else if (_player.state == PlayerState.paused) {
      await _player.resume();
      await _applyVolumeAfterStart();
      _updateState(isPlaying: true);
    } else if (_player.state != PlayerState.playing) {
      await _player.play(DeviceFileSource(path));
      _currentSourcePath = path;
      await _applyVolumeAfterStart();
      _updateState(isPlaying: true, position: Duration.zero);
    }
  }

  void _rebuildPlayOrder() {
    _playOrder = List<int>.generate(_playlist.length, (i) => i);
    if (_playlist.isEmpty) {
      _playOrderIndex = 0;
      return;
    }
    if (_isShuffleEnabled) {
      final current = _currentIndex.clamp(0, _playlist.length - 1);
      _playOrder.remove(current);
      _playOrder.shuffle();
      _playOrder.insert(0, current);
      _playOrderIndex = 0;
    } else {
      _playOrderIndex = _currentIndex.clamp(0, _playlist.length - 1);
    }
  }

  void _syncPlayOrderIndex() {
    if (_playOrder.isEmpty) return;
    final idx = _playOrder.indexOf(_currentIndex);
    _playOrderIndex = idx >= 0 ? idx : 0;
  }

  int? _getNextIndex() {
    if (_playlist.isEmpty) return null;
    if (_isShuffleEnabled) {
      if (_playOrderIndex + 1 < _playOrder.length) return _playOrder[_playOrderIndex + 1];
      return _loopMode == LoopMode.all ? _playOrder.first : null;
    }
    if (_currentIndex < _playlist.length - 1) return _currentIndex + 1;
    return _loopMode == LoopMode.all ? 0 : null;
  }

  int? _getPreviousIndex() {
    if (_playlist.isEmpty) return null;
    if (_isShuffleEnabled) {
      if (_playOrderIndex - 1 >= 0) return _playOrder[_playOrderIndex - 1];
      return _loopMode == LoopMode.all ? _playOrder.last : null;
    }
    if (_currentIndex > 0) return _currentIndex - 1;
    return _loopMode == LoopMode.all ? _playlist.length - 1 : null;
  }

  Future<void> _applyReleaseMode() async {
    final releaseMode = _loopMode == LoopMode.one ? ReleaseMode.loop : ReleaseMode.stop;
    await _player.setReleaseMode(releaseMode);
  }

  Future<void> stop() async {
    _assetLoaded = false; // don't auto-resume asset after playlist ends
    await _player.stop();
    _updateState(isPlaying: false, position: Duration.zero);
  }

  Future<void> play() async {
    // No playlist loaded: don't auto-play any bundled asset.
    if (_playlist.isEmpty) {
      return;
    }
    await _playIndex(_currentIndex, suppressCompletion: true);
  }

  Future<void> pause() async {
    await _player.pause();
    _updateState(isPlaying: false);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updateState(position: position);
  }

  void _updateState({Duration? duration, Duration? position, double? volume, bool? isPlaying, String? currentTitle, String? artist, String? album, int? trackNumber, bool applyMetadata = false, bool? isShuffleEnabled, LoopMode? loopMode, int? currentIndex}) {
    final old = state.value;
    final newDuration = duration ?? old.duration;
    final newPosition = position ?? old.position;
    final newVolume = volume ?? old.volume;
    final newIsPlaying = isPlaying ?? old.isPlaying;
    final newShuffle = isShuffleEnabled ?? old.isShuffleEnabled;
    final newLoop = loopMode ?? old.loopMode;
    final newCurrentIndex = currentIndex ?? old.currentIndex;

    state.value = AudioState(
      isPlaying: newIsPlaying,
      duration: newDuration,
      position: newPosition,
      volume: newVolume,
      currentTitle: applyMetadata ? currentTitle : (currentTitle ?? old.currentTitle),
      artist: applyMetadata ? artist : (artist ?? old.artist),
      album: applyMetadata ? album : (album ?? old.album),
      trackNumber: applyMetadata ? trackNumber : (trackNumber ?? old.trackNumber),
      isShuffleEnabled: newShuffle,
      loopMode: newLoop,
      currentIndex: newCurrentIndex,
    );
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    _lastVolume = clamped;
    await _player.setVolume(clamped);
    _updateState(volume: clamped);
  }

  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;
    _rebuildPlayOrder();
    _updateState(isShuffleEnabled: _isShuffleEnabled);
  }

  Future<void> setShuffle(bool enable) async {
    _isShuffleEnabled = enable;
    _rebuildPlayOrder();
    _updateState(isShuffleEnabled: _isShuffleEnabled);
  }

  Future<void> cycleLoopMode() async {
    final current = _loopMode;
    final next = current == LoopMode.off
        ? LoopMode.all
        : current == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    _loopMode = next;
    await _applyReleaseMode();
    _updateState(loopMode: next);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _applyReleaseMode();
    _updateState(loopMode: mode);
  }

  Future<void> playAtIndex(int index) async {
    if (_playlist.isEmpty) return;
    final clamped = index.clamp(0, _playlist.length - 1);
    await _playIndex(clamped, suppressCompletion: true);
  }

  Future<void> clearPlaylist({bool stopPlayback = true}) async {
    _isPlaylistMode = false;
    if (stopPlayback) {
      await stop();
    }
    _playlist = [];
    _playOrder = [];
    _playOrderIndex = 0;
    _currentIndex = 0;
    _currentSourcePath = null;
    _lastHandledIndex = null;
    _metadataCache.clear();
    _metadataMtimeCache.clear();
    _isCddaPlaylist = false;
    _indexController.add(_currentIndex);
    _updateState(
      currentTitle: null,
      artist: null,
      album: null,
      trackNumber: null,
      currentIndex: _currentIndex,
      applyMetadata: true,
      duration: Duration.zero,
      position: Duration.zero,
      isPlaying: false,
    );
  }

  Future<void> _applyVolumeAfterStart() async {
    if (_lastVolume < 0.0 || _lastVolume > 1.0) return;
    await Future.delayed(const Duration(milliseconds: 30));
    await _player.setVolume(_lastVolume);
  }

  Future<void> _precacheMetadata() async {
    if (_isCddaPlaylist) return;
    for (final path in _playlist) {
      if (!_metadataCache.containsKey(path)) {
        // readMetadata sama zapisuje do cache
        await _readMetadata(path);
        // małe opóźnienie aby nie zlagować UI
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> refreshMetadataForPlaylist() async {
    if (_playlist.isEmpty) return;
    if (_isCddaPlaylist) return;
    final currentPath = (_currentIndex >= 0 && _currentIndex < _playlist.length)
        ? _playlist[_currentIndex]
        : null;
    var currentChanged = false;

    for (final path in _playlist) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          _metadataCache.remove(path);
          _metadataMtimeCache.remove(path);
          if (path == currentPath) {
            currentChanged = true;
          }
        } else {
          final mtime = await file.lastModified();
          final cachedMtime = _metadataMtimeCache[path];
          if (cachedMtime == null || mtime.isAfter(DateTime.fromMillisecondsSinceEpoch(cachedMtime))) {
            await _readMetadata(path);
          }
        }
      } catch (e) {
        debugPrint('Błąd podczas odświeżania metadanych dla $path: $e');
      }
    }

    if (currentChanged) {
      await _handleIndexChange(_currentIndex, source: 'refreshMetadata');
    }
  }

  Future<AudioMetadata> _readMetadata(String path, {bool forceRefresh = false}) async {
    final cached = _metadataCache[path];
    if (cached != null && !forceRefresh) return cached;

    if (_isCddaPlaylist) {
      final meta = AudioMetadata(title: p.basename(path));
      _metadataCache[path] = meta;
      return meta;
    }

    // Spróbuj cache trwałego (mtime+size)
    int? mtimeMs;
    int? sizeBytes;
    if (!forceRefresh) {
      try {
        final f = File(path);
        if (await f.exists()) {
          mtimeMs = (await f.lastModified()).millisecondsSinceEpoch;
          sizeBytes = await f.length();
          final persisted = await MetadataCacheStore.instance.tryGet(
            path,
            mtimeMs: mtimeMs,
            sizeBytes: sizeBytes,
          );
          if (persisted != null) {
            _metadataMtimeCache[path] = mtimeMs;
            _metadataCache[path] = persisted;
            return persisted;
          }
        }
      } catch (_) {
        // cisza: fallback do normalnego odczytu
      }
    }

    String? title;
    String? artist;
    String? album;
    int? trackNumber;
    Uint8List? coverBytes;
    String? coverMime;
    String? coverPath;
    String? lyrics;

    try {
      final file = File(path);
      if (await file.exists()) {
        _metadataMtimeCache[path] = (await file.lastModified()).millisecondsSinceEpoch;
        final tagProcessor = TagProcessor();
        final tags = await tagProcessor.getTagsFromByteArray(file.readAsBytes());
        if (tags.isNotEmpty) {
          final tag = tags.first;
          final rawMap = tag.tags as Map;
          final Map<String, dynamic> map = { for (final e in rawMap.entries) e.key.toString().toLowerCase(): e.value };
          String? pickStr(List<String> keys) {
            for (final k in keys) {
              final v = map[k];
              if (v != null && v.toString().trim().isNotEmpty) {
                return v.toString();
              }
            }
            return null;
          }

          title = pickStr(['title', 'tit2', 'tt2']);
          artist = pickStr(['artist', 'tpe1']);
          album = pickStr(['album', 'talb']);
          lyrics = pickStr(['lyrics', 'uslt', 'sylt', 'unsyncedlyrics']);

          final trackRaw = pickStr(['trck', 'track', 'tracknumber']);
          if (trackRaw != null) {
            final m = RegExp(r'^(\d+)').firstMatch(trackRaw.trim());
            if (m != null) trackNumber = int.tryParse(m.group(1)!);
          }

          // Spróbuj wyciągnąć osadzoną okładkę
          final artKeys = ['apic', 'attached picture', 'coverart', 'metadata_block_picture'];
          for (final k in artKeys) {
            final v = map[k];
            if (v != null) {
              if (v is Uint8List) {
                coverBytes = v;
                coverMime = 'image/jpeg';
                break;
              } else if (v is List<int>) {
                coverBytes = Uint8List.fromList(v);
                coverMime = 'image/jpeg';
                break;
              } else if (v is String) {
                try {
                  coverBytes = base64Decode(v);
                  coverMime = 'image/jpeg';
                  break;
                } catch (_) {}
              }
            }
          }
        }

        // Fallback: FLAC Vorbis Comments i picture block
        final lowerPath = path.toLowerCase();
        if (lowerPath.endsWith('.flac')) {
          if (coverBytes == null) {
            final pic = await _readFlacPicture(file);
            if (pic != null) {
              coverBytes = pic.bytes;
              coverMime = pic.mime;
            }
          }
          final vorbis = await _readFlacVorbisComments(file);
          if (vorbis != null) {
            String? pickVC(String key) => vorbis[key.toLowerCase()];

            String? pickLyricsFromVorbis() {
              final candidates = <String>[];
              void addIfPresent(String? value) {
                if (value != null && value.trim().isNotEmpty) {
                  candidates.add(value.trim());
                }
              }

              addIfPresent(pickVC('lyrics'));
              addIfPresent(pickVC('unsyncedlyrics'));

              for (final entry in vorbis.entries) {
                final key = entry.key.toLowerCase();
                if (key.startsWith('lyrics:') || key.startsWith('unsyncedlyrics:')) {
                  addIfPresent(entry.value);
                }
              }

              if (candidates.isEmpty) return null;
              for (final candidate in candidates) {
                if (_looksSyncedLyrics(candidate)) return candidate;
              }
              return candidates.first;
            }

            title = title ?? pickVC('title');
            artist = artist ?? (pickVC('artist') ?? pickVC('albumartist'));
            album = album ?? pickVC('album');

            final vorbisLyrics = pickLyricsFromVorbis();
            if (vorbisLyrics != null) {
              final hasCurrent = lyrics != null && lyrics.trim().isNotEmpty;
              if (!hasCurrent) {
                lyrics = vorbisLyrics;
              } else if (!_looksSyncedLyrics(lyrics) && _looksSyncedLyrics(vorbisLyrics)) {
                lyrics = vorbisLyrics;
              }
            }

            final trackRaw = pickVC('tracknumber') ?? pickVC('track');
            if (trackRaw != null) {
              final m = RegExp(r'^(\d+)').firstMatch(trackRaw.trim());
              if (m != null) trackNumber = int.tryParse(m.group(1)!);
            }
          }
        }

        // Fallback: ID3v1 dla MP3
        final lower = path.toLowerCase();
        if (lower.endsWith('.mp3') && (title == null && artist == null)) {
          final v1 = await _readId3v1(file);
          if (v1 != null) {
            title = title ?? v1.title;
            artist = artist ?? v1.artist;
            album = album ?? v1.album;
            trackNumber = trackNumber ?? v1.trackNumber;
          }
        }

        // Fallback okładki: pliki w folderze
        if (coverBytes == null || coverBytes.isEmpty) {
          try {
            final dir = file.parent;
            final candidates = [
              'cover.jpg','cover.png','folder.jpg','folder.png','front.jpg','front.png','album.jpg','album.png'
            ];
            for (final name in candidates) {
              final pth = p.join(dir.path, name);
              final f = File(pth);
              if (await f.exists()) {
                coverPath = pth;
                final ext = p.extension(pth).toLowerCase();
                coverMime = ext == '.png' ? 'image/png' : 'image/jpeg';
                break;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Nie udało się odczytać metadanych dla $path: $e');
    }

    final meta = AudioMetadata(
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      coverBytes: coverBytes,
      coverMime: coverMime,
      coverPath: coverPath,
      lyrics: lyrics,
    );

    // Jeśli mamy bytes okładki – zcache'uj do pliku i ustaw coverPath na ścieżkę cache.
    if (mtimeMs != null && sizeBytes != null && coverBytes != null && coverBytes.isNotEmpty) {
      final cachedCoverPath = await MetadataCacheStore.instance.putCoverBytes(
        trackPath: path,
        mtimeMs: mtimeMs,
        sizeBytes: sizeBytes,
        bytes: coverBytes,
        mime: coverMime ?? 'image/jpeg',
      );
      if (cachedCoverPath != null) {
        // preferuj trwały coverPath, nie trzymaj bytes w RAM jeśli nie trzeba
        final metaWithCover = AudioMetadata(
          title: meta.title,
          artist: meta.artist,
          album: meta.album,
          trackNumber: meta.trackNumber,
          coverBytes: null,
          coverMime: meta.coverMime,
          coverPath: cachedCoverPath,
          lyrics: meta.lyrics,
        );
        _metadataCache[path] = metaWithCover;
        await MetadataCacheStore.instance.putMetadata(
          path,
          mtimeMs: mtimeMs,
          sizeBytes: sizeBytes,
          meta: metaWithCover,
        );
              return metaWithCover;
      }
    }

    _metadataCache[path] = meta;
    if (mtimeMs != null && sizeBytes != null) {
      await MetadataCacheStore.instance.putMetadata(
        path,
        mtimeMs: mtimeMs,
        sizeBytes: sizeBytes,
        meta: meta,
      );
    }

    return meta;
  }

  /// Publiczny stream indeksu aktualnie odtwarzanego utworu.
  Stream<int?> get currentIndexStream => _indexController.stream;

  int? _parseCdTrackNumber(String path) {
    final name = p.basename(path);
    final match = RegExp(r'(?:Track\s*)?(\d+)').firstMatch(name);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  void _sortPlaylistForCd() {
    if (_playlist.isEmpty) return;
    final currentPath = (_currentIndex >= 0 && _currentIndex < _playlist.length)
        ? _playlist[_currentIndex]
        : null;

    _playlist.sort((a, b) {
      final aNum = _parseCdTrackNumber(a);
      final bNum = _parseCdTrackNumber(b);
      if (aNum != null && bNum != null && aNum != bNum) {
        return aNum.compareTo(bNum);
      }
      if (aNum != null && bNum == null) return -1;
      if (aNum == null && bNum != null) return 1;
      return p.basename(a).compareTo(p.basename(b));
    });

    if (currentPath != null) {
      final idx = _playlist.indexOf(currentPath);
      _currentIndex = idx >= 0 ? idx : 0;
    } else {
      _currentIndex = 0;
    }
    _rebuildPlayOrder();
  }

  bool _isSamePlaylist(List<String> paths) {
    if (_playlist.length != paths.length) return false;
    for (var i = 0; i < _playlist.length; i++) {
      if (_playlist[i] != paths[i]) return false;
    }
    return true;
  }

  /// Parser Vorbis Comments z kontenera FLAC.
  Future<Map<String, String>?> _readFlacVorbisComments(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final sig = await raf.read(4);
      if (sig.length != 4 || sig[0] != 0x66 || sig[1] != 0x4C || sig[2] != 0x61 || sig[3] != 0x43) {
        return null;
      }
      bool last = false;
      while (!last) {
        final header = await raf.read(4);
        if (header.length != 4) return null;
        last = (header[0] & 0x80) != 0;
        final blockType = header[0] & 0x7F;
        final length = (header[1] << 16) | (header[2] << 8) | header[3];
        if (blockType == 4) {
          final data = await raf.read(length);
          int off = 0;
          int readLE32() {
            if (off + 4 > data.length) return -1;
            final v = data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24);
            off += 4;
            return v;
          }

          String readUtf8N(int n) {
            final end = off + n;
            if (end > data.length) return '';
            final bytes = data.sublist(off, end);
            off = end;
            try {
              return utf8.decode(bytes);
            } catch (_) {
              return latin1.decode(bytes, allowInvalid: true);
            }
          }

          final vendorLen = readLE32();
          if (vendorLen < 0) return null;
          readUtf8N(vendorLen);
          final userCount = readLE32();
          if (userCount < 0) return null;
          final out = <String, String>{};
          for (int i = 0; i < userCount; i++) {
            final clen = readLE32();
            if (clen < 0) break;
            final entry = readUtf8N(clen);
            final eq = entry.indexOf('=');
            if (eq > 0) {
              final k = entry.substring(0, eq).toLowerCase();
              final v = entry.substring(eq + 1).trim();
              if (v.isNotEmpty) out[k] = v;
            }
          }
          return out;
        } else {
          await raf.setPosition((await raf.position()) + length);
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Prosty parser ID3v1/ID3v1.1 dla MP3 (ostatnie 128 bajtów)
  Future<AudioMetadata?> _readId3v1(File file) async {
    try {
      final len = await file.length();
      if (len < 128) return null;
      final raf = await file.open();
      try {
        await raf.setPosition(len - 128);
        final bytes = await raf.read(128);
        if (bytes.length != 128) return null;
        if (bytes[0] != 0x54 || bytes[1] != 0x41 || bytes[2] != 0x47) {
          return null;
        }
        String readString(int start, int length) {
          final sub = bytes.sublist(start, start + length);
          final str = latin1.decode(sub, allowInvalid: true).trim();
          return str.isEmpty ? '' : str;
        }

        final title = readString(3, 30);
        final artist = readString(33, 30);
        final album = readString(63, 30);
        int? trackNumber;
        if (bytes[125] == 0) {
          final tn = bytes[126];
          if (tn > 0) trackNumber = tn;
        }
        return AudioMetadata(
          title: title.isEmpty ? null : title,
          artist: artist.isEmpty ? null : artist,
          album: album.isEmpty ? null : album,
          trackNumber: trackNumber,
        );
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Odczytaj osadzoną okładkę z FLAC METADATA_BLOCK_PICTURE (typ 6).
  Future<_FlacPicture?> _readFlacPicture(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final sig = await raf.read(4);
      if (sig.length != 4 || sig[0] != 0x66 || sig[1] != 0x4C || sig[2] != 0x61 || sig[3] != 0x43) {
        return null;
      }
      bool last = false;
      while (!last) {
        final header = await raf.read(4);
        if (header.length != 4) return null;
        last = (header[0] & 0x80) != 0;
        final blockType = header[0] & 0x7F;
        final length = (header[1] << 16) | (header[2] << 8) | header[3];
        if (blockType == 6) {
          final data = await raf.read(length);
          int off = 0;
          int readBE32() {
            if (off + 4 > data.length) return -1;
            final v = (data[off] << 24) | (data[off + 1] << 16) | (data[off + 2] << 8) | data[off + 3];
            off += 4;
            return v;
          }

          Uint8List readN(int n) {
            final end = off + n;
            if (end > data.length) return Uint8List(0);
            final bytes = Uint8List.fromList(data.sublist(off, end));
            off = end;
            return bytes;
          }

          final picType = readBE32();
          if (picType < 0) return null;
          final mimeLen = readBE32();
          if (mimeLen < 0) return null;
          final mimeBytes = readN(mimeLen);
          final mime = mimeBytes.isEmpty ? null : latin1.decode(mimeBytes, allowInvalid: true).trim();
          final descLen = readBE32();
          if (descLen < 0) return null;
          readN(descLen);
          final width = readBE32();
          final height = readBE32();
          final depth = readBE32();
          final colors = readBE32();
          if ([width, height, depth, colors].any((v) => v < 0)) return null;
          final dataLen = readBE32();
          if (dataLen <= 0) return null;
          final img = readN(dataLen);
          if (img.isEmpty) return null;

          String resolvedMime = (mime == null || mime.isEmpty || mime == '--') ? '' : mime;
          if (resolvedMime.isEmpty) {
            if (img.length >= 8 && img[0] == 0x89 && img[1] == 0x50 && img[2] == 0x4E && img[3] == 0x47) {
              resolvedMime = 'image/png';
            } else if (img.length >= 3 && img[0] == 0xFF && img[1] == 0xD8 && img[2] == 0xFF) {
              resolvedMime = 'image/jpeg';
            } else {
              resolvedMime = 'application/octet-stream';
            }
          }
          return _FlacPicture(bytes: img, mime: resolvedMime);
        } else {
          await raf.setPosition((await raf.position()) + length);
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<void> _loadLikedTracks() async {
    if (_likedLoaded) return;
    _likedLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_prefsLikedTracks) ?? <String>[];
    _likedPaths
      ..clear()
      ..addAll(items);
    likedPaths.value = Set<String>.from(_likedPaths);
  }

  bool isLiked(String path) {
    return _likedPaths.contains(path);
  }

  Future<void> toggleLike(String path) async {
    await _loadLikedTracks();
    if (_likedPaths.contains(path)) {
      _likedPaths.remove(path);
    } else {
      _likedPaths.add(path);
    }
    likedPaths.value = Set<String>.from(_likedPaths);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsLikedTracks, _likedPaths.toList());
  }
}

/// Prosty, niemutowalny stan odtwarzacza dla UI.
class AudioState {
  final bool isPlaying;
  final Duration duration;
  final Duration position;
  final double volume;
  final String? currentTitle;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int currentIndex;

  AudioState({
    required this.isPlaying,
    required this.duration,
    required this.position,
    required this.volume,
    this.currentTitle,
    this.artist,
    this.album,
    this.trackNumber,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.off,
    this.currentIndex = 0,
  });

  factory AudioState.initial() => AudioState(
        isPlaying: false,
        duration: Duration.zero,
        position: Duration.zero,
        volume: 1.0,
        currentIndex: 0,
      );

  AudioState copyWith({
    bool? isPlaying,
    Duration? duration,
    Duration? position,
    double? volume,
    String? currentTitle,
    String? artist,
    String? album,
    int? trackNumber,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? currentIndex,
  }) {
    return AudioState(
      isPlaying: isPlaying ?? this.isPlaying,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      volume: volume ?? this.volume,
      currentTitle: currentTitle ?? this.currentTitle,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      trackNumber: trackNumber ?? this.trackNumber,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

/// Reprezentacja okładki z bloku FLAC PICTURE.
class _FlacPicture {
  _FlacPicture({required this.bytes, required this.mime});
  final Uint8List bytes;
  final String mime;
}


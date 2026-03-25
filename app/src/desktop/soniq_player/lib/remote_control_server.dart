import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_controller.dart';
import 'audio_device_service.dart';
import 'file_upload_service.dart';
import 'library/library_controller.dart';
import 'library/library_models.dart';
import 'library/library_player_screen.dart';
import 'main.dart' show rootNavigatorKey;
import 'playlists/playlists_controller.dart';

class RemoteControlServer extends ChangeNotifier {
  RemoteControlServer._();

  static final RemoteControlServer instance = RemoteControlServer._();
  static const int defaultPort = 8787;
  static const String _prefsVisualizer = 'remoteShowVisualizer';
  static const String _prefsLyrics = 'remoteShowLyrics';
  static const String _backlightPath = '/sys/class/backlight/10-0045/brightness';
  static const int _brightnessMin = 1;
  static const int _brightnessMax = 31;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSub;
  final Set<WebSocket> _clients = {};
  final FileUploadService _uploadService = FileUploadService();
  final AudioDeviceService _audioDeviceService = AudioDeviceService();

  bool _running = false;
  String? _token;
  int? _port;
  String? _ip;
  String? _pairCode;
  bool _showVisualizer = false;
  bool _showLyrics = false;
  String? _cachedSelectedAudioDevice;

  bool get isRunning => _running;
  String? get token => _token;
  int? get port => _port;
  String? get ip => _ip;
  String? get pairCode => _pairCode;
  bool get showVisualizer => _showVisualizer;
  bool get showLyrics => _showLyrics;

  String? get wsUrl {
    if (_ip == null || _port == null || _token == null) return null;
    return 'ws://$_ip:$_port/ws?token=$_token';
  }

  String? get wsUrlWithCode {
    if (_ip == null || _port == null || _pairCode == null) return null;
    return 'ws://$_ip:$_port/ws?code=$_pairCode';
  }

  Future<void> start({int? port, String? token}) async {
    final requestedPort = port ?? _port ?? defaultPort;
    final requestedToken = (token != null && token.isNotEmpty) ? token : _token;

    if (_running) {
      if (_port == requestedPort && _token == requestedToken) return;
      await stop();
    }

    final audio = AudioController();
    if (!audio.isInitialized) {
      await audio.init();
    }
    await _loadRemotePrefs();

    _token = (requestedToken != null && requestedToken.isNotEmpty)
        ? requestedToken
        : _generateToken();
    _pairCode = _generatePairCode();
    _ip = await _pickLanIp() ?? '127.0.0.1';

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, requestedPort, shared: true);
    } catch (_) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }

    _port = _server!.port;
    _running = true;
    notifyListeners();

    audio.state.addListener(_onAudioState);
    _serverSub = _server!.listen(_handleRequest, onError: (_) {}, onDone: () {});

    // Inicjalizuj bibliotekę jeśli jeszcze nie jest zaindeksowana
    _ensureLibraryIndexed();
  }

  void _ensureLibraryIndexed() {
    final lib = LibraryController.instance;
    if (lib.index.value.tracks.isNotEmpty || lib.isIndexing.value) return;
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return;
    final sources = <String, String>{};
    final musicCandidates = [
      p.join(home, 'Music'),
      p.join(home, 'Muzyka'),
    ];
    for (final c in musicCandidates) {
      if (Directory(c).existsSync()) {
        sources['music'] = c;
        break;
      }
    }
    final downloadsCandidates = [
      p.join(home, 'Downloads', 'Music'),
      p.join(home, 'Pobrane', 'Muzyka'),
    ];
    for (final c in downloadsCandidates) {
      if (Directory(c).existsSync()) {
        sources['downloads'] = c;
        break;
      }
    }
    if (sources.isNotEmpty) {
      lib.scheduleRebuild(sources);
    }
  }

  Future<void> stop() async {
    if (!_running) return;

    AudioController().state.removeListener(_onAudioState);
    for (final client in _clients.toList()) {
      await client.close(WebSocketStatus.normalClosure);
    }
    _clients.clear();

    await _serverSub?.cancel();
    await _server?.close(force: true);

    _server = null;
    _serverSub = null;
    _running = false;
    _token = null;
    _pairCode = null;
    _port = null;
    _ip = null;
    notifyListeners();
  }

  Future<void> _loadRemotePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _showVisualizer = prefs.getBool(_prefsVisualizer) ?? false;
    _showLyrics = prefs.getBool(_prefsLyrics) ?? false;
    _cachedSelectedAudioDevice = prefs.getString('selectedAudioDevice');
  }

  Future<void> _persistRemotePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsVisualizer, _showVisualizer);
    await prefs.setBool(_prefsLyrics, _showLyrics);
  }

  Future<void> setRemoteVisualizer(bool value) async {
    _showVisualizer = value;
    await _persistRemotePrefs();
    _broadcast(_buildStatePayload());
    notifyListeners();
  }

  Future<void> setRemoteLyrics(bool value) async {
    _showLyrics = value;
    await _persistRemotePrefs();
    _broadcast(_buildStatePayload());
    notifyListeners();
  }

  Future<String?> _pickLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generatePairCode() {
    final rng = Random.secure();
    final code = rng.nextInt(1000000);
    return code.toString().padLeft(6, '0');
  }

  void _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/ws') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final token = request.uri.queryParameters['token'];
    final code = request.uri.queryParameters['code'];
    final tokenOk = token != null && token == _token;
    final codeOk = code != null && code == _pairCode;
    if (!tokenOk && !codeOk) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    _clients.add(socket);

    socket.done.whenComplete(() {
      _clients.remove(socket);
    });

    _sendSnapshot(socket);

    socket.listen(
      (message) => _handleMessage(socket, message),
      onError: (_) => _clients.remove(socket),
      onDone: () => _clients.remove(socket),
    );
  }

  void _handleMessage(WebSocket socket, dynamic message) async {
    if (message is! String) return;
    final data = _parseJson(message);
    if (data == null) return;

    final type = data['type'];
    final audio = AudioController();

    switch (type) {
      case 'getState':
        _sendSnapshot(socket);
        return;
      case 'play':
        await audio.play();
        return;
      case 'pause':
        await audio.pause();
        return;
      case 'toggle':
        if (audio.state.value.isPlaying) {
          await audio.pause();
        } else {
          await audio.play();
        }
        return;
      case 'next':
        await audio.next();
        return;
      case 'previous':
        await audio.previous();
        return;
      case 'stop':
        await audio.stop();
        return;
      case 'seek':
        final posMs = _numToInt(data['positionMs']);
        if (posMs != null) {
          await audio.seek(Duration(milliseconds: posMs));
        }
        return;
      case 'setVolume':
        final volume = _numToDouble(data['volume']);
        if (volume != null) {
          await audio.setVolume(volume);
        }
        return;
      case 'setShuffle':
        final enable = data['enabled'];
        if (enable is bool) {
          await audio.setShuffle(enable);
        }
        return;
      case 'cycleLoop':
        await audio.cycleLoopMode();
        return;
      case 'setLoopMode':
        final mode = _loopModeFromString(data['mode']);
        if (mode != null) {
          await audio.setLoopMode(mode);
        }
        return;
      case 'playIndex':
        final idx = _numToInt(data['index']);
        if (idx != null) {
          await audio.playAtIndex(idx);
        }
        return;
      case 'getLibraryArtists':
        _sendLibraryArtists(socket);
        return;
      case 'getLibraryAlbums':
        _sendLibraryAlbums(socket, data['artist']?.toString());
        return;
      case 'getLibraryTracks':
        _sendLibraryTracks(socket, artist: data['artist']?.toString(), album: data['album']?.toString());
        return;
      case 'loadPlaylist':
        final paths = data['paths'];
        final startIdx = _numToInt(data['index']) ?? 0;
        if (paths is List) {
          final pathList = paths.map((e) => e.toString()).toList();
          if (pathList.isNotEmpty) {
            await audio.loadPlaylist(pathList, startIndex: startIdx, fromUserPlaylist: true);
            await audio.play();
            _openPlayerScreen();
          }
        }
        return;
      case 'uploadFileStart':
        await _handleUploadFileStart(socket, data);
        return;
      case 'uploadFileChunk':
        await _handleUploadFileChunk(socket, data);
        return;
      case 'uploadFileEnd':
        await _handleUploadFileEnd(socket, data);
        return;
      case 'uploadCancel':
        await _handleUploadCancel(socket, data);
        return;
      case 'likeTrack':
        await _handleLikeTrack(socket, data);
        return;
      case 'addTrackToPlaylist':
        await _handleAddTrackToPlaylist(socket, data);
        return;
      case 'getPlaylists':
        await _handleGetPlaylists(socket, data);
        return;
      case 'getPlaylistDetails':
        await _handleGetPlaylistDetails(socket, data);
        return;
      case 'createPlaylist':
        await _handleCreatePlaylist(socket, data);
        return;
      case 'getBrowseSources':
        await _handleGetBrowseSources(socket, data);
        return;
      case 'getBrowseSourceTracks':
        await _handleGetBrowseSourceTracks(socket, data);
        return;
      case 'getAudioDevices':
        await _handleGetAudioDevices(socket, data);
        return;
      case 'setAudioDevice':
        await _handleSetAudioDevice(socket, data);
        return;
      case 'getBrightness':
        await _handleGetBrightness(socket, data);
        return;
      case 'setBrightness':
        await _handleSetBrightness(socket, data);
        return;
      case 'setVisualizer':
        await _handleSetVisualizer(socket, data);
        return;
      case 'setLyrics':
        await _handleSetLyrics(socket, data);
        return;
      default:
        return;
    }
  }

  Future<void> _handleLikeTrack(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final path = data['path']?.toString();
    if (path == null || path.isEmpty) {
      _sendWsError(socket, requestId, 'likeTrack', 'Brak pola path');
      return;
    }
    final audio = AudioController();
    final liked = audio.isLiked(path);
    await audio.toggleLike(path);
    socket.add(jsonEncode({'type': 'ack', 'action': 'likeTrack', 'requestId': requestId, 'ok': true, 'path': path, 'liked': !liked}));
    _broadcast(_buildStatePayload());
  }

  Future<void> _handleAddTrackToPlaylist(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final playlistId = data['playlistId']?.toString();
    final path = data['path']?.toString();
    if (playlistId == null || playlistId.isEmpty || path == null || path.isEmpty) {
      _sendWsError(socket, requestId, 'addTrackToPlaylist', 'Wymagane: playlistId i path');
      return;
    }
    final playlists = PlaylistsController.instance;
    await playlists.ensureLoaded();
    final playlist = playlists.getById(playlistId);
    if (playlist == null) {
      _sendWsError(socket, requestId, 'addTrackToPlaylist', 'Playlista nie istnieje');
      return;
    }
    await playlists.addTrack(playlistId: playlistId, path: path);
    socket.add(jsonEncode({'type': 'ack', 'action': 'addTrackToPlaylist', 'requestId': requestId, 'ok': true, 'playlistId': playlistId, 'path': path}));
    await _sendPlaylists(socket);
  }

  Future<void> _handleGetPlaylists(WebSocket socket, Map<String, dynamic> data) async {
    await _sendPlaylists(socket, requestId: data['requestId']);
  }

  Future<void> _handleCreatePlaylist(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final name = data['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      _sendWsError(socket, requestId, 'createPlaylist', 'Brak nazwy playlisty');
      return;
    }

    final playlists = PlaylistsController.instance;
    final id = await playlists.createPlaylist(name);
    socket.add(jsonEncode({
      'type': 'ack',
      'action': 'createPlaylist',
      'requestId': requestId,
      'ok': true,
      'playlistId': id,
      'name': name,
    }));
    await _sendPlaylists(socket, requestId: requestId);
  }

  Future<void> _sendPlaylists(WebSocket socket, {dynamic requestId}) async {
    final playlists = PlaylistsController.instance;
    await playlists.ensureLoaded();
    socket.add(jsonEncode({
      'type': 'playlists',
      'requestId': requestId,
      'items': playlists.playlists
          .map((pl) => {
                'id': pl.id,
                'name': pl.name,
                'count': pl.items.length,
                'updatedAtEpochMs': pl.updatedAtEpochMs,
              })
          .toList(),
    }));
  }

  Future<void> _handleGetAudioDevices(WebSocket socket, Map<String, dynamic> data) async {
    final devices = await _audioDeviceService.getOutputDevices();
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('selectedAudioDevice');
    socket.add(jsonEncode({
      'type': 'audioDevices',
      'requestId': data['requestId'],
      'selected': selected,
      'items': devices
          .map((d) => {
                'id': d.name,
                'name': d.name,
                'description': d.description,
              })
          .toList(),
    }));
  }

  Future<void> _handleSetAudioDevice(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final deviceId = data['deviceId']?.toString();
    if (deviceId == null || deviceId.isEmpty) {
      _sendWsError(socket, requestId, 'setAudioDevice', 'Brak deviceId');
      return;
    }
    try {
      await _audioDeviceService.setOutputDevice(deviceId);
    } catch (e) {
      _sendWsError(socket, requestId, 'setAudioDevice', 'Nie udało się ustawić urządzenia audio: $e');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedAudioDevice', deviceId);
    _cachedSelectedAudioDevice = deviceId;
    socket.add(jsonEncode({
      'type': 'ack',
      'action': 'setAudioDevice',
      'requestId': requestId,
      'ok': true,
      'deviceId': deviceId,
    }));
    _broadcast(_buildStatePayload());
    await _handleGetAudioDevices(socket, {'requestId': requestId});
  }

  Future<void> _handleGetBrightness(WebSocket socket, Map<String, dynamic> data) async {
    final level = await _getBrightnessRaw();
    if (level == null) {
      _sendWsError(socket, data['requestId'], 'getBrightness',
          'Nie udało się odczytać brightness. Sprawdź uprawnienia $_backlightPath');
      return;
    }
    socket.add(jsonEncode({
      'type': 'brightness',
      'requestId': data['requestId'],
      'level': level,
      'min': _brightnessMin,
      'max': _brightnessMax,
    }));
  }

  Future<void> _handleSetBrightness(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final level = _numToInt(data['level']);
    if (level == null) {
      _sendWsError(socket, requestId, 'setBrightness', 'Brak lub błędny poziom brightness (1–31)');
      return;
    }
    final clamped = level.clamp(_brightnessMin, _brightnessMax);
    final ok = await _setBrightnessRaw(clamped);
    if (!ok) {
      _sendWsError(socket, requestId, 'setBrightness',
          'Nie udało się ustawić brightness. Sprawdź uprawnienia $_backlightPath');
      return;
    }
    final current = await _getBrightnessRaw();
    socket.add(jsonEncode({
      'type': 'ack',
      'action': 'setBrightness',
      'requestId': requestId,
      'ok': true,
      'level': current ?? clamped,
      'min': _brightnessMin,
      'max': _brightnessMax,
    }));
  }

  /// Odczytuje poziom jasności (1–31) bezpośrednio z /sys/class/backlight/10-0045/brightness.
  Future<int?> _getBrightnessRaw() async {
    try {
      final f = File(_backlightPath);
      if (await f.exists()) {
        final raw = int.tryParse((await f.readAsString()).trim());
        if (raw != null) {
          return raw.clamp(_brightnessMin, _brightnessMax);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Zapisuje poziom jasności (1–31) bezpośrednio do /sys/class/backlight/10-0045/brightness.
  Future<bool> _setBrightnessRaw(int level) async {
    try {
      final f = File(_backlightPath);
      await f.writeAsString('$level');
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> _handleSetVisualizer(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final enabled = data['enabled'];
    if (enabled is! bool) {
      _sendWsError(socket, requestId, 'setVisualizer', 'Brak pola enabled');
      return;
    }
    await setRemoteVisualizer(enabled);
    socket.add(jsonEncode({
      'type': 'ack',
      'action': 'setVisualizer',
      'requestId': requestId,
      'ok': true,
      'enabled': enabled,
    }));
  }

  Future<void> _handleSetLyrics(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final enabled = data['enabled'];
    if (enabled is! bool) {
      _sendWsError(socket, requestId, 'setLyrics', 'Brak pola enabled');
      return;
    }
    await setRemoteLyrics(enabled);
    socket.add(jsonEncode({
      'type': 'ack',
      'action': 'setLyrics',
      'requestId': requestId,
      'ok': true,
      'enabled': enabled,
    }));
  }

  Future<void> _handleGetPlaylistDetails(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final playlistId = data['playlistId']?.toString();
    if (playlistId == null || playlistId.isEmpty) {
      _sendWsError(socket, requestId, 'getPlaylistDetails', 'Brak playlistId');
      return;
    }

    final playlists = PlaylistsController.instance;
    await playlists.ensureLoaded();
    final playlist = playlists.getById(playlistId);
    if (playlist == null) {
      _sendWsError(socket, requestId, 'getPlaylistDetails', 'Playlista nie istnieje');
      return;
    }

    final audio = AudioController();
    final tracks = <Map<String, dynamic>>[];
    for (final item in playlist.items) {
      final meta = await audio.getMetadata(item.path);
      tracks.add({
        'itemId': item.id,
        'path': item.path,
        'title': meta.title?.trim().isNotEmpty == true ? meta.title!.trim() : p.basename(item.path),
        'artist': meta.artist,
        'album': meta.album,
        'trackNumber': meta.trackNumber,
        'addedAtEpochMs': item.addedAtEpochMs,
        'liked': audio.isLiked(item.path),
      });
    }

    socket.add(jsonEncode({
      'type': 'playlistDetails',
      'requestId': requestId,
      'playlist': {
        'id': playlist.id,
        'name': playlist.name,
        'count': playlist.items.length,
        'updatedAtEpochMs': playlist.updatedAtEpochMs,
      },
      'tracks': tracks,
    }));
  }

  Future<void> _handleGetBrowseSources(WebSocket socket, Map<String, dynamic> data) async {
    final items = await _buildBrowseSources();
    socket.add(jsonEncode({
      'type': 'browseSources',
      'requestId': data['requestId'],
      'items': items,
    }));
  }

  Future<void> _handleGetBrowseSourceTracks(WebSocket socket, Map<String, dynamic> data) async {
    final requestId = data['requestId'];
    final sourceId = data['sourceId']?.toString();
    if (sourceId == null || sourceId.isEmpty) {
      _sendWsError(socket, requestId, 'getBrowseSourceTracks', 'Brak sourceId');
      return;
    }

    final sources = await _buildBrowseSources();
    final source = sources.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['sourceId'] == sourceId,
      orElse: () => null,
    );
    if (source == null) {
      _sendWsError(socket, requestId, 'getBrowseSourceTracks', 'Źródło nie istnieje');
      return;
    }

    final tracks = await _tracksForBrowseSource(source);
    socket.add(jsonEncode({
      'type': 'browseSourceTracks',
      'requestId': requestId,
      'source': source,
      'tracks': tracks,
      'count': tracks.length,
    }));
  }

  void _sendLibraryArtists(WebSocket socket) {
    final artists = LibraryController.instance.index.value.artists
        .map((a) => a.name)
        .toList();

    if (artists.isEmpty) {
      socket.add(jsonEncode({
        'type': 'libraryArtists',
        'artists': <String>[],
        'message': 'Biblioteka jest pusta albo nie została jeszcze zeskanowana.',
      }));
      return;
    }

    socket.add(jsonEncode({
      'type': 'libraryArtists',
      'artists': artists,
    }));
  }

  void _sendLibraryAlbums(WebSocket socket, String? artistFilter) {
    var albums = LibraryController.instance.index.value.albums;

    if (artistFilter != null && artistFilter.isNotEmpty) {
      albums = albums.where((a) => a.artistKey == artistFilter).toList();
    }

    socket.add(jsonEncode({
      'type': 'libraryAlbums',
      'albums': albums
          .map((a) => {
                'name': a.name,
                'artist': a.artistKey,
              })
          .toList(),
    }));
  }

  void _sendLibraryTracks(WebSocket socket, {String? artist, String? album}) {
    List<LibraryTrack> tracks;

    final index = LibraryController.instance.index.value;

    if (artist != null && (album == null || album.isEmpty)) {
      final artistObj = index.artists.firstWhere(
        (a) => a.name == artist,
        orElse: () => LibraryArtist(name: '', tracks: []),
      );
      tracks = artistObj.tracks;
    } else if (album != null && album.isNotEmpty) {
      final albumObjs = index.albums.where((a) => a.name == album);
      if (artist != null && artist.isNotEmpty) {
        final specificAlbum = albumObjs.firstWhere(
          (a) => a.artistKey == artist,
          orElse: () => LibraryAlbum(name: '', artistKey: '', tracks: []),
        );
        tracks = specificAlbum.tracks;
      } else {
        tracks = albumObjs.expand((a) => a.tracks).toList();
      }
    } else {
      tracks = index.tracks;
    }

    socket.add(jsonEncode({
      'type': 'libraryTracks',
      'tracks': tracks
          .map((t) => {
                'path': t.path,
                'title': t.titleOrFileName,
                'artist': t.artistOrUnknown,
                'album': t.albumOrUnknown,
                'trackNumber': t.meta.trackNumber,
              })
          .toList(),
    }));
  }

  Future<List<Map<String, dynamic>>> _buildBrowseSources() async {
    final home = Platform.environment['HOME'] ?? '';

    List<String> firstExisting(List<String> cands) {
      for (final c in cands) {
        if (c.isNotEmpty && Directory(c).existsSync()) return [c];
      }
      return cands.isNotEmpty ? [cands.first] : <String>[];
    }

    final musicCandidates = [
      if (home.isNotEmpty) p.join(home, 'Music'),
      if (home.isNotEmpty) p.join(home, 'Muzyka'),
    ];
    final downloadsMusicCandidates = [
      if (home.isNotEmpty) p.join(home, 'Downloads', 'Music'),
      if (home.isNotEmpty) p.join(home, 'Pobrane', 'Muzyka'),
    ];

    final usbDirs = <Map<String, dynamic>>[];
    try {
      final mediaDir = Directory('/media');
      if (mediaDir.existsSync()) {
        for (final entity in mediaDir.listSync(followLinks: false)) {
          if (entity is Directory) {
            usbDirs.add({
              'sourceId': 'usb:${entity.path}',
              'name': 'usb:${p.basename(entity.path)}',
              'label': 'USB ${p.basename(entity.path)}',
              'kind': 'directory',
              'path': entity.path,
              'available': true,
              'isPlaylistShortcut': false,
              'isLastPlayedShortcut': false,
            });
          }
        }
      }
    } catch (_) {}

    final baseSources = <Map<String, dynamic>>[
      {
        'sourceId': 'last_played',
        'name': 'last_played',
        'label': 'Last played',
        'kind': 'lastPlayed',
        'available': AudioController().playlist.isNotEmpty,
        'isPlaylistShortcut': false,
        'isLastPlayedShortcut': true,
      },
      {
        'sourceId': 'favorites',
        'name': 'favorites',
        'label': 'Favorites',
        'kind': 'favorites',
        'available': AudioController().likedPaths.value.isNotEmpty,
        'isPlaylistShortcut': true,
        'isLastPlayedShortcut': false,
      },
      {
        'sourceId': 'music',
        'name': 'music',
        'label': 'Music',
        'kind': 'directory',
        'path': firstExisting(musicCandidates).isNotEmpty ? firstExisting(musicCandidates).first : '',
        'available': firstExisting(musicCandidates).isNotEmpty,
        'isPlaylistShortcut': false,
        'isLastPlayedShortcut': false,
      },
      {
        'sourceId': 'downloads',
        'name': 'downloads',
        'label': 'Downloads',
        'kind': 'directory',
        'path': firstExisting(downloadsMusicCandidates).isNotEmpty ? firstExisting(downloadsMusicCandidates).first : '',
        'available': firstExisting(downloadsMusicCandidates).isNotEmpty,
        'isPlaylistShortcut': false,
        'isLastPlayedShortcut': false,
      },
      {
        'sourceId': 'network',
        'name': 'network',
        'label': 'Network',
        'kind': 'directory',
        'path': '/media/share/Media/Music',
        'available': Directory('/media/share/Media/Music').existsSync(),
        'isPlaylistShortcut': false,
        'isLastPlayedShortcut': false,
      },
      {
        'sourceId': 'local',
        'name': 'local',
        'label': 'Local',
        'kind': 'directory',
        'path': '/mnt/music',
        'available': Directory('/mnt/music').existsSync(),
        'isPlaylistShortcut': false,
        'isLastPlayedShortcut': false,
      },
    ];

    return [...baseSources, ...usbDirs];
  }

  Future<List<Map<String, dynamic>>> _tracksForBrowseSource(Map<String, dynamic> source) async {
    final audio = AudioController();
    final kind = source['kind']?.toString();
    List<String> paths = [];

    if (kind == 'favorites') {
      paths = audio.likedPaths.value.toList();
    } else if (kind == 'lastPlayed') {
      paths = audio.playlist.toList();
    } else {
      final dirPath = source['path']?.toString() ?? '';
      if (dirPath.isNotEmpty) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          const allowed = {'.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'};
          paths = dir
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) => allowed.contains(p.extension(f.path).toLowerCase()))
              .map((f) => f.path)
              .toList()
            ..sort();
        }
      }
    }

    final tracks = <Map<String, dynamic>>[];
    for (final path in paths) {
      final meta = await audio.getMetadata(path);
      tracks.add({
        'path': path,
        'title': meta.title?.trim().isNotEmpty == true ? meta.title!.trim() : p.basename(path),
        'artist': meta.artist,
        'album': meta.album,
        'trackNumber': meta.trackNumber,
        'liked': audio.isLiked(path),
      });
    }
    return tracks;
  }

  void _onAudioState() {
    _broadcast(_buildStatePayload());
  }

  void _sendSnapshot(WebSocket socket) {
    socket.add(jsonEncode(_buildStatePayload()));
  }

  void _broadcast(Map<String, dynamic> payload) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(payload);
    for (final client in _clients.toList()) {
      try {
        client.add(encoded);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  Map<String, dynamic> _buildStatePayload() {
    final audio = AudioController();
    final state = audio.state.value;
    final playlist = audio.playlist.map((path) => {'path': path, 'name': p.basename(path), 'liked': audio.isLiked(path)}).toList();

    // Odczytaj wybrane urządzenie synchronicznie (cached w SharedPreferences)
    String? selectedDevice;
    try {
      // SharedPreferences.getInstance() jest async, używamy synchronicznego dostępu
      // przez instancję — jeśli już załadowana, działa synchronicznie
      selectedDevice = _cachedSelectedAudioDevice;
    } catch (_) {}

    return {
      'type': 'state',
      'isPlaying': state.isPlaying,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'volume': state.volume,
      'currentIndex': audio.currentIndex,
      'title': state.currentTitle,
      'artist': state.artist,
      'album': state.album,
      'trackNumber': state.trackNumber,
      'isShuffleEnabled': state.isShuffleEnabled,
      'loopMode': state.loopMode.name,
      'playlist': playlist,
      'showVisualizer': _showVisualizer,
      'showLyrics': _showLyrics,
      'selectedAudioDevice': selectedDevice,
      'brightnessMin': _brightnessMin,
      'brightnessMax': _brightnessMax,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic>? _parseJson(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  int? _numToInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return null;
  }

  double? _numToDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  void _sendWsError(WebSocket socket, dynamic requestId, String action, String message) {
    socket.add(jsonEncode({
      'type': 'error',
      'action': action,
      'requestId': requestId,
      'message': message,
    }));
  }

  LoopMode? _loopModeFromString(dynamic value) {
    if (value is! String) return null;
    for (final mode in LoopMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  Future<void> _handleUploadFileStart(WebSocket socket, Map<String, dynamic> data) async {
    final filename = data['filename']?.toString() ?? '';
    final totalSizeBytes = _numToInt(data['totalSizeBytes']);
    final targetDirName = data['targetDir']?.toString() ?? 'Music'; // Domyślnie 'Music'

    if (filename.isEmpty || totalSizeBytes == null || totalSizeBytes <= 0) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'error': 'Brakuje parametrów: filename, totalSizeBytes',
      });
      return;
    }

    final targetDir = _getUploadTargetDirectory(targetDirName);
    if (targetDir == null) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'error': 'Nie znaleziono katalogu docelowego: $targetDirName',
      });
      return;
    }

    final sessionId = await _uploadService.startUpload(
      filename: filename,
      totalSizeBytes: totalSizeBytes,
      targetDirectory: targetDir,
    );

    if (sessionId == null) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'error': 'Nie udało się zainicjalizować uploadu',
      });
      return;
    }

    _sendJsonToSocket(socket, {
      'type': 'uploadStart',
      'sessionId': sessionId,
    });
  }

  Future<void> _handleUploadFileChunk(WebSocket socket, Map<String, dynamic> data) async {
    final sessionId = data['sessionId']?.toString() ?? '';
    final chunkBase64 = data['chunk']?.toString() ?? '';

    if (sessionId.isEmpty || chunkBase64.isEmpty) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'sessionId': sessionId,
        'error': 'Brakuje parametrów: sessionId, chunk',
      });
      return;
    }

    final result = await _uploadService.addChunk(
      sessionId: sessionId,
      chunkBase64: chunkBase64,
    );

    if (result['success'] == false) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'sessionId': sessionId,
        'error': result['error'] ?? 'Błąd zapisywania chunk',
      });
      return;
    }

    _sendJsonToSocket(socket, {
      'type': 'uploadProgress',
      'sessionId': sessionId,
      'percentDone': result['percentDone'],
      'bytesWritten': result['bytesWritten'],
    });
  }

  Future<void> _handleUploadFileEnd(WebSocket socket, Map<String, dynamic> data) async {
    final sessionId = data['sessionId']?.toString() ?? '';

    if (sessionId.isEmpty) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'error': 'Brakuje parametru: sessionId',
      });
      return;
    }

    final result = await _uploadService.finalize(sessionId: sessionId);

    if (result['success'] == false) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'sessionId': sessionId,
        'error': result['error'] ?? 'Błąd finalizacji uploadu',
      });
      return;
    }

    final finalPath = result['path']?.toString() ?? '';
    final finalFilename = result['filename']?.toString() ?? '';

    // Wyzwól auto-skan biblioteki
    await _triggerLibraryScan();

    _sendJsonToSocket(socket, {
      'type': 'uploadComplete',
      'sessionId': sessionId,
      'filename': finalFilename,
      'path': finalPath,
    });

    // Rozwyślij informację do wszystkich klientów o nowym pliku
    _broadcast({
      'type': 'fileUploaded',
      'filename': finalFilename,
      'path': finalPath,
    });
  }

  Future<void> _handleUploadCancel(WebSocket socket, Map<String, dynamic> data) async {
    final sessionId = data['sessionId']?.toString() ?? '';

    if (sessionId.isEmpty) {
      _sendJsonToSocket(socket, {
        'type': 'uploadError',
        'error': 'Brakuje parametru: sessionId',
      });
      return;
    }

    await _uploadService.cancel(sessionId);

    _sendJsonToSocket(socket, {
      'type': 'uploadCancelled',
      'sessionId': sessionId,
    });
  }

  /// Uzyskaj pełną ścieżkę katalogu docelowego na podstawie nazwy.
  /// Obsługuje: 'Music', 'Muzyka' oraz katalogi z HOME.
  String? _getUploadTargetDirectory(String dirName) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;

    // Mapuj nazwy katalogów do pełnych ścieżek
    final dirMap = {
      'Music': p.join(home, 'Music'),
      'Muzyka': p.join(home, 'Muzyka'),
    };

    // Zwróć mapowaną ścieżkę, albo spróbuj bezpośrednio
    return dirMap[dirName];
  }

  /// Wyzwól skan biblioteki dla wszystkich dostępnych katalogów muzyki.
  Future<void> _triggerLibraryScan() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final musicCandidates = [
        p.join(home, 'Music'),
        p.join(home, 'Muzyka'),
      ];

      final downloadsMusicCandidates = [
        p.join(home, 'Downloads', 'Music'),
        p.join(home, 'Pobrane', 'Muzyka'),
      ];

      String? firstExisting(List<String> cands) {
        for (final c in cands) {
          if (c.isNotEmpty && Directory(c).existsSync()) return c;
        }
        return null;
      }

      final sources = <String, String>{};

      final musicDir = firstExisting(musicCandidates);
      if (musicDir != null) {
        sources['music'] = musicDir;
      }

      final downloadsDir = firstExisting(downloadsMusicCandidates);
      if (downloadsDir != null) {
        sources['downloads'] = downloadsDir;
      }

      if (sources.isNotEmpty) {
        LibraryController.instance.scheduleRebuild(sources);
      }
    } catch (e, st) {
      debugPrint('Błąd wyzwalania skanu biblioteki: $e\n$st');
    }
  }

  void _sendJsonToSocket(WebSocket socket, Map<String, dynamic> data) {
    try {
      socket.add(jsonEncode(data));
    } catch (_) {
      _clients.remove(socket);
    }
  }

  void _openPlayerScreen() {
    // Nie próbuj nawigować, jeśli aplikacja nie ma jeszcze gotowego navigatora.
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    // Opcja: zawsze otwieraj dedykowany player bibliotekowy (nie wymaga katalogu).
    // Uwaga: nawigacja musi być zrobiona po zakończeniu aktualnej klatki.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav2 = rootNavigatorKey.currentState;
      if (nav2 == null) return;

      nav2.push(
        MaterialPageRoute(
          builder: (_) => const LibraryPlayerScreen(title: 'Remote Player'),
        ),
      );
    });
  }
}

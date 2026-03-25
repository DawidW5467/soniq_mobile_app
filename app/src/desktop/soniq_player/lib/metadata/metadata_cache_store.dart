import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio_controller.dart';

/// Trwały cache metadanych i okładek.
///
/// Założenia (kiosk):
/// - szybki start po restarcie
/// - brak blokowania UI: każda operacja IO jest async
/// - bezpieczne invalidacje: klucz (path + mtime + size)
class MetadataCacheStore {
  MetadataCacheStore._();
  static final MetadataCacheStore instance = MetadataCacheStore._();

  static const _schemaVersion = 2;

  Directory? _baseDir;
  File? _indexFile;

  bool _loaded = false;
  bool _dirty = false;
  Timer? _flushDebounce;

  /// path -> entry
  final Map<String, _CacheEntry> _entries = {};

  Future<void> init() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _baseDir = Directory(p.join(dir.path, 'soniq_cache'));
      await _baseDir!.create(recursive: true);
      _indexFile = File(p.join(_baseDir!.path, 'metadata_index.json'));

      await _loadIndex();
    } catch (e, st) {
      debugPrint('MetadataCacheStore.init error: $e\n$st');
      // nadal ustaw loaded, żeby nie próbować w kółko
      _loaded = true;
    }
  }

  Future<void> _loadIndex() async {
    if (_indexFile == null) return;
    try {
      if (!await _indexFile!.exists()) {
        _loaded = true;
        return;
      }
      final txt = await _indexFile!.readAsString();
      final decoded = jsonDecode(txt);
      if (decoded is! Map<String, dynamic>) {
        _loaded = true;
        return;
      }
      if ((decoded['schemaVersion'] as int?) != _schemaVersion) {
        // stary format – czyścimy
        _entries.clear();
        _loaded = true;
        return;
      }
      final items = decoded['items'];
      if (items is Map<String, dynamic>) {
        _entries
          ..clear()
          ..addAll(items.map((k, v) => MapEntry(k, _CacheEntry.fromJson(v))));
      }
    } catch (e) {
      debugPrint('MetadataCacheStore._loadIndex error: $e');
    } finally {
      _loaded = true;
    }
  }

  void _markDirty() {
    _dirty = true;
    _flushDebounce?.cancel();
    _flushDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    if (!_dirty) return;
    if (_indexFile == null) return;
    try {
      final payload = <String, dynamic>{
        'schemaVersion': _schemaVersion,
        'items': _entries.map((k, v) => MapEntry(k, v.toJson())),
      };
      await _indexFile!.writeAsString(jsonEncode(payload));
      _dirty = false;
    } catch (e) {
      debugPrint('MetadataCacheStore.flush error: $e');
    }
  }

  /// Zwraca metadane z cache, jeżeli:
  /// - wpis istnieje
  /// - fingerprint (mtime+size) pasuje
  Future<AudioMetadata?> tryGet(String path, {required int mtimeMs, required int sizeBytes}) async {
    await init();
    final e = _entries[path];
    if (e == null) return null;
    if (e.mtimeMs != mtimeMs || e.sizeBytes != sizeBytes) return null;

    return AudioMetadata(
      title: e.title,
      artist: e.artist,
      album: e.album,
      trackNumber: e.trackNumber,
      coverPath: e.coverCachePath,
      coverBytes: null, // nie trzymamy w prefs/index
      coverMime: e.coverMime,
      lyrics: e.lyrics,
    );
  }

  Future<String?> putCoverBytes({required String trackPath, required int mtimeMs, required int sizeBytes, required Uint8List bytes, required String mime}) async {
    await init();
    if (_baseDir == null) return null;

    final ext = _mimeToExt(mime);
    final key = _hashKey('$trackPath|$mtimeMs|$sizeBytes|cover');
    final coverFile = File(p.join(_baseDir!.path, 'covers', '$key$ext'));
    await coverFile.parent.create(recursive: true);

    try {
      if (!await coverFile.exists()) {
        await coverFile.writeAsBytes(bytes, flush: false);
      }
      return coverFile.path;
    } catch (e) {
      debugPrint('MetadataCacheStore.putCoverBytes error: $e');
      return null;
    }
  }

  Future<void> putMetadata(
    String path, {
    required int mtimeMs,
    required int sizeBytes,
    required AudioMetadata meta,
  }) async {
    await init();

    _entries[path] = _CacheEntry(
      mtimeMs: mtimeMs,
      sizeBytes: sizeBytes,
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      trackNumber: meta.trackNumber,
      coverCachePath: meta.coverPath,
      coverMime: meta.coverMime,
      lyrics: meta.lyrics,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _markDirty();
  }

  static String _hashKey(String s) => sha1.convert(utf8.encode(s)).toString();

  static String _mimeToExt(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('png')) return '.png';
    if (m.contains('gif')) return '.gif';
    if (m.contains('webp')) return '.webp';
    return '.jpg';
  }
}

class _CacheEntry {
  _CacheEntry({
    required this.mtimeMs,
    required this.sizeBytes,
    required this.title,
    required this.artist,
    required this.album,
    required this.trackNumber,
    required this.coverCachePath,
    required this.coverMime,
    required this.lyrics,
    required this.updatedAtMs,
  });

  final int mtimeMs;
  final int sizeBytes;
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final String? coverCachePath;
  final String? coverMime;
  final String? lyrics;
  final int updatedAtMs;

  factory _CacheEntry.fromJson(dynamic v) {
    final map = (v is Map) ? v : const <String, dynamic>{};
    int asInt(dynamic x) => x is int ? x : int.tryParse(x?.toString() ?? '') ?? 0;

    return _CacheEntry(
      mtimeMs: asInt(map['mtimeMs']),
      sizeBytes: asInt(map['sizeBytes']),
      title: map['title']?.toString(),
      artist: map['artist']?.toString(),
      album: map['album']?.toString(),
      trackNumber: map['trackNumber'] == null ? null : asInt(map['trackNumber']),
      coverCachePath: map['coverCachePath']?.toString(),
      coverMime: map['coverMime']?.toString(),
      lyrics: map['lyrics']?.toString(),
      updatedAtMs: asInt(map['updatedAtMs']),
    );
  }

  Map<String, dynamic> toJson() => {
        'mtimeMs': mtimeMs,
        'sizeBytes': sizeBytes,
        'title': title,
        'artist': artist,
        'album': album,
        'trackNumber': trackNumber,
        'coverCachePath': coverCachePath,
        'coverMime': coverMime,
        'lyrics': lyrics,
        'updatedAtMs': updatedAtMs,
      };
}

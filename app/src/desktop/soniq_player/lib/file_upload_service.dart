import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Model reprezentujący aktywną sesję uploadu pliku.
class UploadSession {
  final String sessionId;
  final String originalFilename;
  final int totalSizeBytes;
  final String targetDirectory;

  late final IOSink _tempFile;
  final File _tempFileHandle;

  int _bytesWritten = 0;
  DateTime _lastActivity = DateTime.now();
  bool _isCompleted = false;
  String? _error;

  UploadSession({
    required this.sessionId,
    required this.originalFilename,
    required this.totalSizeBytes,
    required this.targetDirectory,
    required File tempFileHandle,
  }) : _tempFileHandle = tempFileHandle;

  int get bytesWritten => _bytesWritten;
  int get percentDone => totalSizeBytes > 0 ? ((_bytesWritten * 100) ~/ totalSizeBytes) : 0;
  DateTime get lastActivity => _lastActivity;
  bool get isCompleted => _isCompleted;
  String? get error => _error;

  Future<void> initTemp() async {
    try {
      _tempFile = _tempFileHandle.openWrite();
    } catch (e) {
      _error = 'Błąd otwierania pliku temp: $e';
      throw _error!;
    }
  }

  /// Zapisz chunk danych do pliku temp.
  /// [chunk] powinien być base64-encoded string.
  Future<void> writeChunk(String chunk) async {
    try {
      _updateActivity();

      // Dekoduj z base64
      final bytes = base64Decode(chunk);

      // Sprawdź czy nie przekraczamy całkowitego rozmiaru
      if (_bytesWritten + bytes.length > totalSizeBytes) {
        _error = 'Chunk przekracza deklarowaną wielkość pliku';
        throw _error!;
      }

      _tempFile.add(bytes);
      _bytesWritten += bytes.length;
    } catch (e) {
      _error = 'Błąd zapisywania chunk: $e';
      rethrow;
    }
  }

  /// Sfinalizuj upload — zamknij plik temp i zwróć finalną ścieżkę.
  Future<String> finalize() async {
    try {
      _updateActivity();

      // Sprawdź czy otrzymaliśmy wszystkie bajty
      if (_bytesWritten != totalSizeBytes) {
        _error = 'Otrzymano $_bytesWritten bajtów, oczekiwano $totalSizeBytes';
        throw _error!;
      }

      await _tempFile.close();

      // Przenieś plik z temp do docelowego katalogu
      final finalPath = await _moveTempToTarget();
      _isCompleted = true;
      return finalPath;
    } catch (e) {
      _error = 'Błąd finalizacji: $e';
      rethrow;
    } finally {
      await cleanup();
    }
  }

  /// Przenieś plik z temp do docelowego katalogu, obsługując duplikaty.
  Future<String> _moveTempToTarget() async {
    final targetDir = Directory(targetDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    var finalPath = p.join(targetDirectory, originalFilename);
    var finalFile = File(finalPath);

    // Obsłuż duplikaty: dodaj sufiks (1), (2), itd.
    if (await finalFile.exists()) {
      final ext = p.extension(originalFilename);
      final nameWithoutExt = p.basenameWithoutExtension(originalFilename);

      int counter = 1;
      while (true) {
        final newName = '$nameWithoutExt ($counter)$ext';
        finalPath = p.join(targetDirectory, newName);
        finalFile = File(finalPath);
        if (!await finalFile.exists()) break;
        counter++;
      }
    }

    // Spróbuj atomowego rename (działa gdy source i dest są na tym samym fs).
    // Jeśli /tmp i katalog docelowy są na różnych urządzeniach (errno=18 EXDEV),
    // fallback do kopiowania + usunięcia pliku tymczasowego.
    try {
      await _tempFileHandle.rename(finalPath);
    } on FileSystemException catch (e) {
      // errno 18 = EXDEV: Invalid cross-device link
      if (e.osError?.errorCode == 18) {
        await _tempFileHandle.copy(finalPath);
        try {
          await _tempFileHandle.delete();
        } catch (_) {}
      } else {
        rethrow;
      }
    }
    return finalPath;
  }

  /// Anuluj upload i wyczyść zasoby.
  Future<void> cancel() async {
    _updateActivity();
    await cleanup();
  }

  /// Wyczyść tymczasowe zasoby.
  Future<void> cleanup() async {
    try {
      await _tempFile.close();
    } catch (_) {}
    try {
      if (await _tempFileHandle.exists()) {
        await _tempFileHandle.delete();
      }
    } catch (_) {}
  }

  void _updateActivity() {
    _lastActivity = DateTime.now();
  }
}

/// Serwis zarządzający uploadami plików.
class FileUploadService {
  FileUploadService._();
  static final FileUploadService _instance = FileUploadService._();

  factory FileUploadService() => _instance;

  static const int _maxFileSizeBytes = 500 * 1024 * 1024; // 500 MB
  static const _allowedExtensions = {'.mp3', '.flac', '.ogg', '.wav', '.aac'};
  static const _sessionTimeoutDuration = Duration(minutes: 30);

  final Map<String, UploadSession> _sessions = {};
  Timer? _timeoutTimer;

  /// Zainicjalizuj upload. Zwróć sessionId lub null przy błędzie.
  Future<String?> startUpload({
    required String filename,
    required int totalSizeBytes,
    required String targetDirectory,
  }) async {
    // Waliduj nazwę pliku
    final validationError = _validateFilename(filename);
    if (validationError != null) {
      debugPrint('FileUploadService: $validationError');
      return null;
    }

    // Waliduj rozmiar
    if (totalSizeBytes <= 0 || totalSizeBytes > _maxFileSizeBytes) {
      debugPrint('FileUploadService: Rozmiar poza dozwolonym zakresem: $totalSizeBytes');
      return null;
    }

    // Waliduj katalog docelowy
    final targetDir = Directory(targetDirectory);
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (e) {
        debugPrint('FileUploadService: Nie udało się utworzyć katalogu docelowego: $e');
        return null;
      }
    }

    // Utwórz sesję
    final sessionId = _generateSessionId();
    final tempFile = File('/tmp/soniq_upload_$sessionId');

    final session = UploadSession(
      sessionId: sessionId,
      originalFilename: filename,
      totalSizeBytes: totalSizeBytes,
      targetDirectory: targetDirectory,
      tempFileHandle: tempFile,
    );

    try {
      await session.initTemp();
      _sessions[sessionId] = session;
      _startTimeoutCheck();
      return sessionId;
    } catch (e) {
      debugPrint('FileUploadService: Błąd inicjalizacji sesji: $e');
      await session.cleanup();
      return null;
    }
  }

  /// Dodaj chunk do aktywnej sesji.
  Future<Map<String, dynamic>> addChunk({
    required String sessionId,
    required String chunkBase64,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return {
        'success': false,
        'error': 'Sesja nie znaleziona: $sessionId',
      };
    }

    try {
      await session.writeChunk(chunkBase64);
      return {
        'success': true,
        'percentDone': session.percentDone,
        'bytesWritten': session.bytesWritten,
      };
    } catch (e) {
      // Błąd — anuluj sesję
      await session.cancel();
      _sessions.remove(sessionId);
      return {
        'success': false,
        'error': '$e',
      };
    }
  }

  /// Sfinalizuj upload.
  Future<Map<String, dynamic>> finalize({
    required String sessionId,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return {
        'success': false,
        'error': 'Sesja nie znaleziona: $sessionId',
      };
    }

    try {
      final finalPath = await session.finalize();
      _sessions.remove(sessionId);
      return {
        'success': true,
        'filename': p.basename(finalPath),
        'path': finalPath,
      };
    } catch (e) {
      await session.cleanup();
      _sessions.remove(sessionId);
      return {
        'success': false,
        'error': '$e',
      };
    }
  }

  /// Anuluj upload.
  Future<void> cancel(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await session.cancel();
    }
  }

  /// Zwróć status sesji.
  Map<String, dynamic>? getStatus(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return null;

    return {
      'sessionId': sessionId,
      'filename': session.originalFilename,
      'percentDone': session.percentDone,
      'bytesWritten': session.bytesWritten,
      'totalSize': session.totalSizeBytes,
      'isCompleted': session.isCompleted,
      'error': session.error,
    };
  }

  /// Wyczyść wszystkie zawieszony uploady starsze niż timeout.
  void _cleanupExpiredSessions() {
    final now = DateTime.now();
    final expired = <String>[];

    for (final entry in _sessions.entries) {
      final age = now.difference(entry.value.lastActivity);
      if (age > _sessionTimeoutDuration) {
        expired.add(entry.key);
      }
    }

    for (final sessionId in expired) {
      debugPrint('FileUploadService: Timeout sesji $sessionId');
      unawaited(_sessions[sessionId]?.cleanup());
      _sessions.remove(sessionId);
    }
  }

  void _startTimeoutCheck() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpiredSessions();
    });
  }

  String _generateSessionId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String? _validateFilename(String filename) {
    // Sprawdź czy plik zawiera ścieżkę (path traversal)
    if (filename.contains('/') || filename.contains('\\')) {
      return 'Nazwa pliku zawiera ścieżkę';
    }

    // Sprawdź rozszerzenie
    final ext = p.extension(filename).toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      return 'Niedozwolone rozszerzenie: $ext. Dozwolone: ${_allowedExtensions.join(', ')}';
    }

    // Sprawdź czy nazwa jest pusta
    if (filename.isEmpty || p.basenameWithoutExtension(filename).isEmpty) {
      return 'Nazwa pliku jest pusta';
    }

    return null;
  }

  void dispose() {
    _timeoutTimer?.cancel();
    for (final session in _sessions.values) {
      unawaited(session.cleanup());
    }
    _sessions.clear();
  }
}


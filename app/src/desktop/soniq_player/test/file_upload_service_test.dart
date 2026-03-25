import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:soniq_player/file_upload_service.dart';

void main() {
  group('FileUploadService', () {
    late FileUploadService uploadService;
    late Directory tempDir;

    setUp(() async {
      uploadService = FileUploadService();
      tempDir = await Directory.systemTemp.createTemp('soniq_test_');
    });

    tearDown(() async {
      uploadService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('startUpload inicjalizuje sesję z poprawnym sessionId', () async {
      final result = await uploadService.startUpload(
        filename: 'test.mp3',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(0));
    });

    test('startUpload zwraca null dla niedozwolonych rozszerzeń', () async {
      final result = await uploadService.startUpload(
        filename: 'test.txt',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      expect(result, isNull);
    });

    test('startUpload zwraca null dla pliku większego niż limit', () async {
      final maxSize = 500 * 1024 * 1024;
      final result = await uploadService.startUpload(
        filename: 'test.mp3',
        totalSizeBytes: maxSize + 1,
        targetDirectory: tempDir.path,
      );

      expect(result, isNull);
    });

    test('startUpload zwraca null dla nazwy z path traversal', () async {
      final result = await uploadService.startUpload(
        filename: '../evil.mp3',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      expect(result, isNull);
    });

    test('addChunk zapisuje dane i zwraca postęp', () async {
      final sessionId = await uploadService.startUpload(
        filename: 'test.mp3',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      expect(sessionId, isNotNull);

      // Utwórz test data (100 bajtów)
      final testData = List<int>.filled(100, 42);
      final base64Chunk = base64Encode(testData);

      final result = await uploadService.addChunk(
        sessionId: sessionId!,
        chunkBase64: base64Chunk,
      );

      expect(result['success'], isTrue);
      expect(result['bytesWritten'], 100);
      expect(result['percentDone'], 9); // ~9% z 1024
    });

    test('addChunk zwraca błąd dla nieistniejącej sesji', () async {
      final result = await uploadService.addChunk(
        sessionId: 'nonexistent',
        chunkBase64: 'data',
      );

      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });

    test('finalize zwraca błąd dla niedokończonego uploadu', () async {
      final sessionId = await uploadService.startUpload(
        filename: 'test.mp3',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      final result = await uploadService.finalize(sessionId: sessionId!);

      expect(result['success'], isFalse);
      expect(result['error'], contains('Otrzymano'));
    });

    test('pełny cykl uploadu — od start do finalize', () async {
      // Inicjalizuj
      const fileSize = 1024;
      final sessionId = await uploadService.startUpload(
        filename: 'complete.mp3',
        totalSizeBytes: fileSize,
        targetDirectory: tempDir.path,
      );

      expect(sessionId, isNotNull);

      // Przesyłaj chunki
      final testData = List<int>.filled(fileSize, 99);
      final base64Chunk = base64Encode(testData);

      final chunkResult = await uploadService.addChunk(
        sessionId: sessionId!,
        chunkBase64: base64Chunk,
      );

      expect(chunkResult['success'], isTrue);
      expect(chunkResult['bytesWritten'], fileSize);
      expect(chunkResult['percentDone'], 100);

      // Finalizuj
      final finalResult = await uploadService.finalize(sessionId: sessionId);

      expect(finalResult['success'], isTrue);
      expect(finalResult['filename'], 'complete.mp3');
      expect(finalResult['path'], isNotNull);

      // Sprawdź czy plik istnieje
      final finalFile = File(finalResult['path']);
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.length(), fileSize);
    });

    test('obsługa duplikatów plików', () async {
      // Utwórz istniejący plik
      final existingFile = File(p.join(tempDir.path, 'duplicate.mp3'));
      await existingFile.writeAsString('existing content');

      // Przesyłaj nowy plik o tej samej nazwie
      const fileSize = 512;
      final sessionId = await uploadService.startUpload(
        filename: 'duplicate.mp3',
        totalSizeBytes: fileSize,
        targetDirectory: tempDir.path,
      );

      final testData = List<int>.filled(fileSize, 88);
      final base64Chunk = base64Encode(testData);

      await uploadService.addChunk(
        sessionId: sessionId!,
        chunkBase64: base64Chunk,
      );

      final finalResult = await uploadService.finalize(sessionId: sessionId);

      expect(finalResult['success'], isTrue);
      // Powinien mieć sufiks
      expect(finalResult['filename'], contains('('));
      expect(finalResult['filename'], endsWith('.mp3'));

      // Sprawdź czy oba pliki istnieją
      expect(await existingFile.exists(), isTrue);
      final newFile = File(finalResult['path']);
      expect(await newFile.exists(), isTrue);
    });

    test('getStatus zwraca informacje sesji', () async {
      final sessionId = await uploadService.startUpload(
        filename: 'status.mp3',
        totalSizeBytes: 2048,
        targetDirectory: tempDir.path,
      );

      final status = uploadService.getStatus(sessionId!);

      expect(status, isNotNull);
      expect(status!['sessionId'], sessionId);
      expect(status['filename'], 'status.mp3');
      expect(status['totalSize'], 2048);
      expect(status['bytesWritten'], 0);
      expect(status['percentDone'], 0);
    });

    test('cancel anuluje upload', () async {
      final sessionId = await uploadService.startUpload(
        filename: 'cancel.mp3',
        totalSizeBytes: 1024,
        targetDirectory: tempDir.path,
      );

      await uploadService.cancel(sessionId!);

      final status = uploadService.getStatus(sessionId);
      expect(status, isNull);
    });
  });
}


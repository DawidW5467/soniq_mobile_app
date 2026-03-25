import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Spawns a cava process and streams the visualizer data.
/// Requires 'cava' to be installed on the system.
class CavaController {
  static final CavaController _instance = CavaController._internal();
  factory CavaController() => _instance;
  CavaController._internal();

  Process? _process;
  StreamSubscription? _stdoutSub;
  final StreamController<List<double>> _dataController = StreamController.broadcast();
  File? _configFile;

  Stream<List<double>> get dataStream => _dataController.stream;

  final int bars = 64; // Number of bars to request from cava

  bool _starting = false;
  DateTime? _lastStartAttempt;
  static bool? _cavaAvailable;
  int _refCount = 0;

  Future<void> start() async {
    _refCount += 1;
    if (_process != null || _starting) return;
    final now = DateTime.now();
    if (_lastStartAttempt != null && now.difference(_lastStartAttempt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastStartAttempt = now;
    _starting = true;

    try {
      // Check if cava exists (only once)
      if (Platform.isLinux) {
        if (_cavaAvailable == null) {
          final checkResult = await Process.run('which', ['cava']);
          _cavaAvailable = checkResult.exitCode == 0;
        }
        if (_cavaAvailable != true) {
          debugPrint('Cava not found. Visualizer disabled.');
          return;
        }
      }

      // Create a temporary config file
      _configFile = File('${Directory.systemTemp.path}/cava_soniq_${Random().nextInt(10000)}.conf');
      await _configFile!.writeAsString(_generateConfig());

      // Start cava
      _process = await Process.start(
        'cava',
        ['-p', _configFile!.path],
        mode: ProcessStartMode.detachedWithStdio,
      );

      // Parse output
      _stdoutSub = _process!.stdout.listen((data) {
        _parseData(data);
      });

      _process!.stderr.listen((data) {
        // debugPrint('[Cava Error] ${utf8.decode(data)}');
      });
    } catch (e) {
      debugPrint('Failed to start cava: $e');
      stop();
    } finally {
      _starting = false;
      if (_process == null) {
        _refCount = _refCount > 0 ? _refCount - 1 : 0;
      }
    }
  }

  void _parseData(List<int> data) {
    // Cava raw output is a stream of bytes (if bit_format=8bit, values 0-255)
    // We expect 'bars' bytes per frame usually, but chunks can be anything.
    // The format with 'raw' and 'ascii' can be tricky (delimiters).
    // Let's use 'raw' data_format and 'ascii' (values separated by newlines or semi-colons is mostly for scripting).
    // The most robust way for raw reading:
    // output block: 'binary', values 0..255 (or 16bit).
    // Let's try to interpret the chunk.
    // If we receive a chunk of `bars` bytes, it's a frame. If multiple, split.
    
    // Since stream chunks are arbitrary, we might need a buffer if frames are split.
    // simplified: just take the latest complete chunk of size `bars`.
    
    if (data.isEmpty) return;
    
    // For 8bit binary output, each byte is one bar value.
    // We try to process as many full frames as possible, or at least the last one.
    
    final frameSize = bars;
    if (data.length < frameSize) return; // Wait for more? (simplification: drop for now)

    // Take the last full frame
    final lastStart = (data.length ~/ frameSize) * frameSize - frameSize;
    if (lastStart < 0) return;

    final frameBytes = data.sublist(lastStart, lastStart + frameSize);
    final values = frameBytes.map((b) => b / 255.0).toList();
    _dataController.add(values);
  }

  String _generateConfig() {
    return '''
[general]
framerate = 30
bars = $bars
autosens = 1

[output]
method = raw
data_format = binary
bit_format = 8bit
channels = mono
''';
  }

  void stop() {
    if (_refCount > 0) {
      _refCount -= 1;
    }
    if (_refCount > 0) {
      return;
    }
    _stdoutSub?.cancel();
    _process?.kill();
    _process = null;
    try {
      if (_configFile != null && _configFile!.existsSync()) {
        _configFile!.deleteSync();
      }
    } catch (_) {}
  }
}

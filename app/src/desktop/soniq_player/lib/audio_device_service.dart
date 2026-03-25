import 'dart:io';
import 'package:flutter/foundation.dart';

class AudioDevice {
  final String name;
  final String description;

  AudioDevice({required this.name, required this.description});

  @override
  String toString() => description;
}

/// Backend audio wykrywany automatycznie.
enum AudioBackend { pactl, wpctl, alsa, none }

class AudioDeviceService {
  AudioBackend? _detectedBackend;

  /// Wykrywa dostępny backend audio (cached).
  Future<AudioBackend> _detectBackend() async {
    if (_detectedBackend != null) return _detectedBackend!;

    // 1. Sprawdź wpctl (WirePlumber / PipeWire natywny — typowy na RPi5)
    if (await _commandAvailable('wpctl')) {
      try {
        final result = await Process.run('wpctl', ['status']);
        if (result.exitCode == 0) {
          _detectedBackend = AudioBackend.wpctl;
          debugPrint('AudioDeviceService: wykryto backend wpctl');
          return _detectedBackend!;
        }
      } catch (_) {}
    }

    // 2. Sprawdź pactl (PulseAudio / PipeWire z pipewire-pulse)
    if (await _commandAvailable('pactl')) {
      try {
        final result = await Process.run('pactl', ['info']);
        if (result.exitCode == 0) {
          _detectedBackend = AudioBackend.pactl;
          debugPrint('AudioDeviceService: wykryto backend pactl');
          return _detectedBackend!;
        }
      } catch (_) {}
    }

    // 3. Sprawdź ALSA (aplay)
    if (await _commandAvailable('aplay')) {
      _detectedBackend = AudioBackend.alsa;
      debugPrint('AudioDeviceService: wykryto backend alsa');
      return _detectedBackend!;
    }

    _detectedBackend = AudioBackend.none;
    debugPrint('AudioDeviceService: brak obsługiwanego backendu audio');
    return _detectedBackend!;
  }

  Future<bool> _commandAvailable(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Resetuje wykryty backend (np. po zmianie konfiguracji systemu).
  void resetBackend() {
    _detectedBackend = null;
  }

  /// Pobiera listę dostępnych urządzeń wyjściowych.
  Future<List<AudioDevice>> getOutputDevices() async {
    final backend = await _detectBackend();
    switch (backend) {
      case AudioBackend.pactl:
        return _getPactlDevices();
      case AudioBackend.wpctl:
        return _getWpctlDevices();
      case AudioBackend.alsa:
        return _getAlsaDevices();
      case AudioBackend.none:
        return [];
    }
  }

  /// Ustawia wybrane urządzenie jako domyślne i przenosi aktywne strumienie.
  Future<void> setOutputDevice(String deviceName) async {
    final backend = await _detectBackend();
    switch (backend) {
      case AudioBackend.pactl:
        await _setPactlDevice(deviceName);
        break;
      case AudioBackend.wpctl:
        await _setWpctlDevice(deviceName);
        break;
      case AudioBackend.alsa:
        await _setAlsaDevice(deviceName);
        break;
      case AudioBackend.none:
        debugPrint('Brak backendu audio - nie można zmienić urządzenia');
        break;
    }
  }

  // ──────────────────────────────────────────────────────────
  // PulseAudio / PipeWire-pulse (pactl)
  // ──────────────────────────────────────────────────────────

  Future<List<AudioDevice>> _getPactlDevices() async {
    try {
      final result = await Process.run('pactl', ['list', 'sinks']);
      if (result.exitCode != 0) {
        debugPrint('Błąd pactl list sinks: ${result.stderr}');
        return [];
      }
      return _parsePactlSinks(result.stdout.toString());
    } catch (e) {
      debugPrint('Wyjątek pactl: $e');
      return [];
    }
  }

  Future<void> _setPactlDevice(String deviceName) async {
    try {
      // 1. Set as default sink
      final setResult = await Process.run('pactl', ['set-default-sink', deviceName]);
      debugPrint('AudioDevice pactl set-default-sink $deviceName -> exit ${setResult.exitCode}');
      if (setResult.exitCode != 0) {
        debugPrint('AudioDevice pactl set-default-sink stderr: ${setResult.stderr}');
      }

      // 2. Find the sink index for the target device
      final sinkIndex = await _getSinkIndex(deviceName);
      debugPrint('AudioDevice sink index for $deviceName = $sinkIndex');

      // 3. Move all active sink-inputs to the new sink
      await _moveAllSinkInputs(deviceName, sinkIndex);

      // 4. Retry after a short delay (some players create streams lazily)
      await Future.delayed(const Duration(milliseconds: 500));
      await _moveAllSinkInputs(deviceName, sinkIndex);

      // 5. On PipeWire systems, also try wpctl as supplementary method
      await _tryWpctlSetDefault(deviceName);
    } catch (e) {
      debugPrint('Błąd pactl setOutputDevice: $e');
    }
  }

  /// Get sink index for a device name
  Future<String?> _getSinkIndex(String deviceName) async {
    try {
      final result = await Process.run('pactl', ['list', 'short', 'sinks']);
      if (result.exitCode != 0) return null;
      // Format: "<index>\t<name>\t<driver>\t<format>\t<state>"
      for (final line in result.stdout.toString().split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == deviceName) {
          return parts[0]; // sink index
        }
      }
    } catch (_) {}
    return null;
  }

  /// Move all active sink-inputs to the target device
  Future<void> _moveAllSinkInputs(String deviceName, String? sinkIndex) async {
    try {
      final inputsResult = await Process.run('pactl', ['list', 'short', 'sink-inputs']);
      if (inputsResult.exitCode != 0) return;

      final output = inputsResult.stdout.toString();
      debugPrint('AudioDevice sink-inputs:\n$output');
      // Short format: "<id>\t<sink-index>\t<client>\t<driver>\t<state>"
      for (final line in output.split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isEmpty || parts.first.isEmpty) continue;
        final id = parts.first;
        // Check if already on correct sink (compare by index)
        if (sinkIndex != null && parts.length > 1 && parts[1] == sinkIndex) continue;

        final moveResult = await Process.run('pactl', ['move-sink-input', id, deviceName]);
        debugPrint('AudioDevice move-sink-input $id -> $deviceName exit ${moveResult.exitCode}');
        if (moveResult.exitCode != 0) {
          debugPrint('AudioDevice move-sink-input stderr: ${moveResult.stderr}');
        }
      }
    } catch (e) {
      debugPrint('AudioDevice _moveAllSinkInputs error: $e');
    }
  }

  /// On PipeWire systems, pactl may detect sinks but not move streams properly.
  /// Try using wpctl as a supplementary method.
  Future<void> _tryWpctlSetDefault(String pactlDeviceName) async {
    try {
      final wpctlAvailable = await _commandAvailable('wpctl');
      if (!wpctlAvailable) return;

      // Map pactl device name to wpctl node id
      final statusResult = await Process.run('wpctl', ['status']);
      if (statusResult.exitCode != 0) return;

      final wpctlId = _findWpctlIdForPactlName(
        statusResult.stdout.toString(),
        pactlDeviceName,
      );

      if (wpctlId != null) {
        final result = await Process.run('wpctl', ['set-default', wpctlId]);
        debugPrint('AudioDevice wpctl set-default $wpctlId -> exit ${result.exitCode}');
      }
    } catch (e) {
      debugPrint('AudioDevice _tryWpctlSetDefault error: $e');
    }
  }

  /// Try to match a pactl device name to a wpctl node id by looking for
  /// a partial match in wpctl status output.
  String? _findWpctlIdForPactlName(String wpctlOutput, String pactlName) {
    // pactl name is like "alsa_output.platform-fef00700.hdmi.hdmi-stereo"
    // wpctl shows descriptions like "Built-in Audio HDMI"
    // We try to match by looking for the wpctl line containing parts of the pactl name

    // Extract distinguishing parts from pactl name
    final nameParts = pactlName.split(RegExp(r'[._-]'));
    final keywords = nameParts
        .where((p) => p.length > 3 && p != 'alsa' && p != 'output' && p != 'platform')
        .map((p) => p.toLowerCase())
        .toList();

    final sinkPattern = RegExp(r'[│|]\s+[*\s]\s*(\d+)\.\s+(.+?)(?:\s+\[.*\])?\s*$');
    bool inSinks = false;

    for (final line in wpctlOutput.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.contains('Sinks:')) {
        inSinks = true;
        continue;
      }
      if (inSinks && (trimmed.contains('Sources:') || trimmed.contains('Filters:') ||
          trimmed.contains('Streams:') || trimmed.startsWith('Video'))) {
        inSinks = false;
        continue;
      }
      if (inSinks) {
        final match = sinkPattern.firstMatch(line);
        if (match != null) {
          final id = match.group(1)!;
          final desc = match.group(2)!.toLowerCase();
          // Check if any keyword from the pactl name appears in the description
          if (keywords.any((kw) => desc.contains(kw))) {
            return id;
          }
        }
      }
    }
    return null;
  }

  List<AudioDevice> _parsePactlSinks(String output) {
    final devices = <AudioDevice>[];
    final lines = output.split('\n');
    String? currentName;
    String? currentDesc;

    for (final line in lines) {
      final trimmed = line.trim();
      if (line.startsWith('Sink #')) {
        if (currentName != null && currentDesc != null) {
          devices.add(AudioDevice(name: currentName, description: currentDesc));
        }
        currentName = null;
        currentDesc = null;
      } else if (trimmed.startsWith('Name: ')) {
        currentName = trimmed.substring(6);
      } else if (trimmed.startsWith('Description: ')) {
        currentDesc = trimmed.substring(13);
      }
    }
    if (currentName != null && currentDesc != null) {
      devices.add(AudioDevice(name: currentName, description: currentDesc));
    }
    return devices;
  }

  // ──────────────────────────────────────────────────────────
  // PipeWire natywny (wpctl / pw-cli) – typowy na Raspberry Pi 5
  // ──────────────────────────────────────────────────────────

  Future<List<AudioDevice>> _getWpctlDevices() async {
    try {
      final result = await Process.run('wpctl', ['status']);
      if (result.exitCode != 0) {
        debugPrint('Błąd wpctl status: ${result.stderr}');
        return [];
      }
      return _parseWpctlSinks(result.stdout.toString());
    } catch (e) {
      debugPrint('Wyjątek wpctl: $e');
      return [];
    }
  }

  Future<void> _setWpctlDevice(String deviceId) async {
    try {
      // wpctl set-default <id>
      await Process.run('wpctl', ['set-default', deviceId]);

      // Próbuj przenieść aktywne strumienie
      final statusResult = await Process.run('wpctl', ['status']);
      if (statusResult.exitCode == 0) {
        final streamIds = _parseWpctlStreams(statusResult.stdout.toString());
        for (final streamId in streamIds) {
          try {
            await Process.run('pw-cli', ['s', streamId, 'Props', '{ target.object = $deviceId }']);
          } catch (_) {
            // pw-cli może nie być dostępny – ignoruj
          }
        }
      }
    } catch (e) {
      debugPrint('Błąd wpctl setOutputDevice: $e');
    }
  }

  /// Parsuje wyjście `wpctl status` i wyciąga sinki z sekcji Audio > Sinks.
  List<AudioDevice> _parseWpctlSinks(String output) {
    final devices = <AudioDevice>[];
    final lines = output.split('\n');
    bool inAudioSection = false;
    bool inSinksSection = false;

    // Wzorzec np.: " │  * 46. Built-in Audio Analog Stereo [vol: 0.74]"
    //          lub: " │    46. Built-in Audio Analog Stereo [vol: 0.74]"
    final sinkPattern = RegExp(r'[│|]\s+[*\s]\s*(\d+)\.\s+(.+?)(?:\s+\[.*\])?\s*$');

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('Audio')) {
        inAudioSection = true;
        inSinksSection = false;
        continue;
      }
      if (trimmed.startsWith('Video') || trimmed.startsWith('Settings')) {
        inAudioSection = false;
        inSinksSection = false;
        continue;
      }

      if (inAudioSection) {
        if (trimmed.contains('Sinks:')) {
          inSinksSection = true;
          continue;
        }
        if (trimmed.contains('Sources:') || trimmed.contains('Filters:') ||
            trimmed.contains('Streams:')) {
          inSinksSection = false;
          continue;
        }

        if (inSinksSection) {
          final match = sinkPattern.firstMatch(line);
          if (match != null) {
            final id = match.group(1)!;
            final description = match.group(2)!.trim();
            devices.add(AudioDevice(name: id, description: description));
          }
        }
      }
    }

    return devices;
  }

  /// Parsuje aktywne strumienie audio z `wpctl status`.
  List<String> _parseWpctlStreams(String output) {
    final streamIds = <String>[];
    final lines = output.split('\n');
    bool inStreamsSection = false;

    final streamPattern = RegExp(r'[│|]\s+[*\s]\s*(\d+)\.\s+');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('Streams:')) {
        inStreamsSection = true;
        continue;
      }
      if (inStreamsSection) {
        if (trimmed.isEmpty || trimmed.startsWith('Video') ||
            trimmed.startsWith('Settings') || trimmed.startsWith('Sources:') ||
            trimmed.startsWith('Sinks:') || trimmed.startsWith('Filters:')) {
          inStreamsSection = false;
          continue;
        }
        final match = streamPattern.firstMatch(line);
        if (match != null) {
          streamIds.add(match.group(1)!);
        }
      }
    }
    return streamIds;
  }

  // ──────────────────────────────────────────────────────────
  // ALSA (aplay / amixer) - prosty fallback
  // ──────────────────────────────────────────────────────────

  Future<List<AudioDevice>> _getAlsaDevices() async {
    try {
      final result = await Process.run('aplay', ['-l']);
      if (result.exitCode != 0) {
        debugPrint('Błąd aplay -l: ${result.stderr}');
        return [];
      }
      return _parseAlsaDevices(result.stdout.toString());
    } catch (e) {
      debugPrint('Wyjątek aplay: $e');
      return [];
    }
  }

  Future<void> _setAlsaDevice(String deviceName) async {
    try {
      final home = Platform.environment['HOME'] ?? '/root';
      final asoundrc = File('$home/.asoundrc');

      final config = '''
pcm.!default {
    type plug
    slave.pcm "$deviceName"
}

ctl.!default {
    type hw
    card $deviceName
}
''';
      await asoundrc.writeAsString(config);
      debugPrint('ALSA: zapisano ~/.asoundrc z urządzeniem $deviceName');
    } catch (e) {
      debugPrint('Błąd ALSA setOutputDevice: $e');
    }
  }

  List<AudioDevice> _parseAlsaDevices(String output) {
    final devices = <AudioDevice>[];
    final lines = output.split('\n');

    // Wzorzec: "card 0: Headphones [bcm2835 Headphones], device 0: ..."
    final cardPattern = RegExp(r'^card\s+(\d+):\s+(\S+)\s+\[(.+?)\],\s+device\s+(\d+):\s+(.+?)\s*\[');

    for (final line in lines) {
      final match = cardPattern.firstMatch(line);
      if (match != null) {
        final cardNum = match.group(1)!;
        final deviceNum = match.group(4)!;
        final fullDesc = match.group(3)!;
        final deviceDesc = match.group(5)!;

        final alsaName = 'hw:$cardNum,$deviceNum';
        final description = '$fullDesc - $deviceDesc';

        devices.add(AudioDevice(name: alsaName, description: description));
      }
    }

    return devices;
  }
}


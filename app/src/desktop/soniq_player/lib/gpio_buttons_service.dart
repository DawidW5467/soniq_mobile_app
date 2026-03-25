import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef GpioAction = FutureOr<void> Function();

class GpioButtonConfig {
  const GpioButtonConfig({
    required this.pin,
    required this.onPressed,
    this.activeLow = true,
  });

  final int pin;
  final GpioAction onPressed;
  final bool activeLow;
}

class GpioButtonsService {
  static final GpioButtonsService instance = GpioButtonsService._internal();

  GpioButtonsService._internal();

  final Map<int, GpioButtonConfig> _configs = {};
  final Map<int, DateTime> _lastPressAt = {};

  // gpiomon-based monitoring
  final List<Process> _gpiomonProcesses = [];

  bool _started = false;
  bool _logPresses = false;
  Duration _debounce = const Duration(milliseconds: 300);

  void start({
    required List<GpioButtonConfig> buttons,
    Duration debounce = const Duration(milliseconds: 300),
    bool logPresses = false,
  }) {
    if (_started) return;
    _started = true;
    _logPresses = logPresses;
    _debounce = debounce;

    if (!Platform.isLinux) {
      _started = false;
      return;
    }

    for (final cfg in buttons) {
      _configs[cfg.pin] = cfg;
    }

    // Start async — try gpiomon first, then gpioget-based polling
    _startAsync(buttons);
  }

  Future<void> _startAsync(List<GpioButtonConfig> buttons) async {
    // Kill any leftover gpiomon processes from a previous app run
    await _killStaleGpiomonProcesses();

    final chipPath = await _detectGpioChip(buttons.first.pin);
    if (chipPath == null) {
      debugPrint('GPIO: nie znaleziono odpowiedniego gpiochip dla pinów.');
      _started = false;
      return;
    }

    debugPrint('GPIO: używam chipa $chipPath');

    // Determine which version of gpiomon is available
    final gpiomonVersion = await _detectGpiomonVersion();
    debugPrint('GPIO: gpiomon wersja = $gpiomonVersion');

    if (gpiomonVersion == _GpiomonVersion.v2) {
      await _startGpiomonV2(chipPath, buttons);
    } else if (gpiomonVersion == _GpiomonVersion.v1) {
      await _startGpiomonV1(chipPath, buttons);
    } else {
      // No gpiomon — fall back to gpioget polling
      debugPrint('GPIO: brak gpiomon, próbuję gpioget polling...');
      final gpiogetAvailable = await _commandAvailable('gpioget');
      if (gpiogetAvailable) {
        _startGpiogetPolling(chipPath, buttons);
      } else {
        debugPrint('GPIO: brak gpioget — GPIO nieobsługiwane.');
        _started = false;
      }
    }
  }

  /// Detect the correct GPIO chip for the given pin.
  /// On RPi5 the user-facing GPIO is typically gpiochip4 (RP1).
  /// On RPi4 and older it's gpiochip0.
  Future<String?> _detectGpioChip(int testPin) async {
    // Prefer explicit chip detection via gpioinfo if available.
    if (await _commandAvailable('gpioinfo')) {
      // Try known RPi5 chip first (gpiochip4), then iterate.
      final candidates = <String>[];
      try {
        final dir = Directory('/dev');
        if (dir.existsSync()) {
          final regex = RegExp(r'^gpiochip(\d+)$');
          final entries = dir.listSync(followLinks: false);
          final chips = <int>[];
          for (final entry in entries) {
            final name = entry.path.split('/').last;
            final match = regex.firstMatch(name);
            if (match != null) {
              chips.add(int.parse(match.group(1)!));
            }
          }
          // Sort: try gpiochip4 first (RPi5), then descending
          chips.sort((a, b) {
            if (a == 4) return -1;
            if (b == 4) return 1;
            return b.compareTo(a);
          });
          candidates.addAll(chips.map((c) => '/dev/gpiochip$c'));
        }
      } catch (_) {}

      for (final chip in candidates) {
        // Verify the chip has the requested pin by trying gpioget
        try {
          final chipName = chip.split('/').last;
          final result = await Process.run(
            'gpioget',
            ['--bias=pull-up', chipName, testPin.toString()],
          ).timeout(const Duration(seconds: 2));
          if (result.exitCode == 0) {
            debugPrint('GPIO: chip $chip działa dla pinu $testPin');
            return chipName;
          }
        } catch (_) {
          // Try v1 syntax: gpioget <chip> <pin>
          try {
            final chipName = chip.split('/').last;
            final result = await Process.run(
              'gpioget',
              [chipName, testPin.toString()],
            ).timeout(const Duration(seconds: 2));
            if (result.exitCode == 0) {
              debugPrint('GPIO: chip $chip działa dla pinu $testPin (v1 syntax)');
              return chipName;
            }
          } catch (_) {}
        }
      }
    }

    // Fallback: try known chip paths
    for (final chipNum in [4, 0, 1, 2, 3]) {
      final path = '/dev/gpiochip$chipNum';
      if (File(path).existsSync()) {
        return 'gpiochip$chipNum';
      }
    }
    return null;
  }

  Future<bool> _commandAvailable(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Kill any gpiomon processes left over from a previous app instance.
  Future<void> _killStaleGpiomonProcesses() async {
    try {
      // Find all gpiomon processes
      final result = await Process.run('pgrep', ['-f', 'gpiomon']);
      if (result.exitCode != 0) return; // no processes found

      final pids = result.stdout.toString().trim().split('\n');
      for (final pidStr in pids) {
        final pid = int.tryParse(pidStr.trim());
        if (pid == null || pid <= 0) continue;
        try {
          await Process.run('kill', [pid.toString()]);
          debugPrint('GPIO: zabito stary proces gpiomon (PID $pid)');
        } catch (_) {}
      }
      // Wait briefly for processes to actually die
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint('GPIO: nie udało się zabić starych procesów gpiomon: $e');
    }
  }

  Future<_GpiomonVersion> _detectGpiomonVersion() async {
    if (!await _commandAvailable('gpiomon')) {
      return _GpiomonVersion.none;
    }
    // gpiomon v2 (libgpiod >=2.0) has --help that shows different syntax
    try {
      final result = await Process.run('gpiomon', ['--help']);
      final output = '${result.stdout}${result.stderr}';
      // v2 uses: gpiomon [OPTIONS] <chip> <line> ...
      // v1 uses: gpiomon [OPTIONS] <chip name/number> <offset 1> ...
      // v2 has --chip option or different flags
      if (output.contains('--chip') || output.contains('--banner')) {
        return _GpiomonVersion.v2;
      }
      return _GpiomonVersion.v1;
    } catch (_) {
      return _GpiomonVersion.v1;
    }
  }

  /// Start gpiomon v2 (libgpiod 2.x) — one process monitoring all lines.
  /// Syntax: `gpiomon --chip CHIP --bias=pull-up --edges=falling LINE1 LINE2 ...`
  Future<void> _startGpiomonV2(String chipName, List<GpioButtonConfig> buttons) async {
    final pins = buttons.map((b) => b.pin.toString()).toList();
    final allActiveLow = buttons.every((b) => b.activeLow);
    final edgeArg = allActiveLow ? 'falling' : 'rising';

    // Try multiple v2 syntax variants — different libgpiod 2.x versions differ
    final syntaxVariants = <List<String>>[
      ['--chip', chipName, '--bias=pull-up', '--edges=$edgeArg', ...pins],
      ['--chip', chipName, '--bias=pull-up', '--event=$edgeArg', ...pins],
      ['--chip', chipName, '--bias=pull-up', '--edge=$edgeArg', ...pins],
      ['--chip', chipName, '--bias=pull-up', '-e', edgeArg, ...pins],
      // Without bias
      ['--chip', chipName, '--edges=$edgeArg', ...pins],
      ['--chip', chipName, '--event=$edgeArg', ...pins],
      ['--chip', chipName, '-e', edgeArg, ...pins],
    ];

    for (final args in syntaxVariants) {
      debugPrint('GPIO: próbuję gpiomon v2: gpiomon ${args.join(' ')}');

      try {
        final process = await Process.start('gpiomon', args);

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          debugPrint('GPIO gpiomon v2 stderr: $line');
        });

        // Wait briefly to see if process exits immediately with error
        await Future.delayed(const Duration(milliseconds: 500));

        // Check if still running
        final exitCode = await process.exitCode.timeout(
          const Duration(milliseconds: 100),
          onTimeout: () => -999, // still running
        );

        if (exitCode == -999) {
          // Process is running — success!
          debugPrint('GPIO: gpiomon v2 uruchomiony pomyślnie: gpiomon ${args.join(' ')}');
          _gpiomonProcesses.add(process);

          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            _handleGpiomonLine(line);
          });

          process.exitCode.then((code) {
            debugPrint('GPIO gpiomon v2 exited with code $code');
            // Auto-fallback to gpioget polling if gpiomon dies
            if (_started && _gpiomonProcesses.isEmpty) {
              debugPrint('GPIO: gpiomon padł, fallback na gpioget polling');
              _startGpiogetPolling(chipName, buttons);
            }
          });
          return; // Success — stop trying variants
        }

        // Process exited — try next variant
        debugPrint('GPIO: gpiomon v2 wariant nie zadziałał (exit code $exitCode)');
      } catch (e) {
        debugPrint('GPIO: gpiomon v2 wariant rzucił wyjątek: $e');
      }
    }

    // All v2 variants failed — fallback to v1
    debugPrint('GPIO: wszystkie warianty gpiomon v2 zawiodły, próbuję v1...');
    await _startGpiomonV1(chipName, buttons);
  }

  /// Start gpiomon v1 (libgpiod 1.x).
  /// Syntax: `gpiomon --bias=pull-up --falling-edge chipname offset1 offset2 ...`
  Future<void> _startGpiomonV1(String chipName, List<GpioButtonConfig> buttons) async {
    final pins = buttons.map((b) => b.pin.toString()).toList();
    final allActiveLow = buttons.every((b) => b.activeLow);

    final syntaxVariants = <List<String>>[
      ['--bias=pull-up', if (allActiveLow) '--falling-edge' else '--rising-edge', chipName, ...pins],
      [if (allActiveLow) '--falling-edge' else '--rising-edge', chipName, ...pins],
      ['--bias=pull-up', chipName, ...pins],
      [chipName, ...pins],
    ];

    for (final args in syntaxVariants) {
      debugPrint('GPIO: próbuję gpiomon v1: gpiomon ${args.join(' ')}');

      try {
        final process = await Process.start('gpiomon', args);

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          debugPrint('GPIO gpiomon v1 stderr: $line');
        });

        // Wait briefly to see if process exits immediately with error
        await Future.delayed(const Duration(milliseconds: 500));

        final exitCode = await process.exitCode.timeout(
          const Duration(milliseconds: 100),
          onTimeout: () => -999,
        );

        if (exitCode == -999) {
          // Process is running — success!
          debugPrint('GPIO: gpiomon v1 uruchomiony pomyślnie: gpiomon ${args.join(' ')}');
          _gpiomonProcesses.add(process);

          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            _handleGpiomonLine(line);
          });

          process.exitCode.then((code) {
            debugPrint('GPIO gpiomon v1 exited with code $code');
            if (_started && _gpiomonProcesses.isEmpty) {
              debugPrint('GPIO: gpiomon v1 padł, fallback na gpioget polling');
              _startGpiogetPolling(chipName, buttons);
            }
          });
          return;
        }

        debugPrint('GPIO: gpiomon v1 wariant nie zadziałał (exit code $exitCode)');
      } catch (e) {
        debugPrint('GPIO: gpiomon v1 wariant rzucił wyjątek: $e');
      }
    }

    // All v1 variants failed — fallback to gpioget polling
    debugPrint('GPIO: wszystkie warianty gpiomon zawiodły, fallback na gpioget polling');
    final gpiogetAvailable = await _commandAvailable('gpioget');
    if (gpiogetAvailable) {
      _startGpiogetPolling(chipName, buttons);
    } else {
      debugPrint('GPIO: brak gpioget — GPIO nieobsługiwane.');
      _started = false;
    }
  }

  /// Handle a line from gpiomon output.
  /// v1 format: `timestamp FALLING EDGE offset: pin event #N on gpiochipX`
  /// v2 format varies but contains the offset number
  void _handleGpiomonLine(String line) {
    if (_logPresses) {
      debugPrint('GPIO gpiomon event: $line');
    }

    // Extract pin number from line
    // v1: "... offset: 23 ..."  or  "... offset:  23 ..."
    // v2: might be different but still contains the offset
    int? pin;

    // Try v1 pattern: "offset: <N>"
    final offsetMatch = RegExp(r'offset:\s*(\d+)').firstMatch(line);
    if (offsetMatch != null) {
      pin = int.tryParse(offsetMatch.group(1)!);
    }

    // Try v2 pattern: line might contain "line  <N>"  or just the pin number
    if (pin == null) {
      final lineMatch = RegExp(r'line\s+(\d+)').firstMatch(line);
      if (lineMatch != null) {
        pin = int.tryParse(lineMatch.group(1)!);
      }
    }

    // Fallback: find any known pin number in the line
    if (pin == null) {
      for (final knownPin in _configs.keys) {
        if (RegExp('\\b$knownPin\\b').hasMatch(line)) {
          pin = knownPin;
          break;
        }
      }
    }

    if (pin == null) return;

    final cfg = _configs[pin];
    if (cfg == null) return;

    // Debounce
    final now = DateTime.now();
    final lastAt = _lastPressAt[pin];
    if (lastAt != null && now.difference(lastAt) < _debounce) {
      return;
    }
    _lastPressAt[pin] = now;

    if (_logPresses) {
      debugPrint('GPIO press detected on pin $pin (gpiomon)');
    }

    _invoke(cfg.onPressed);
  }

  /// Fallback: poll with gpioget command
  Timer? _pollTimer;

  void _startGpiogetPolling(String chipName, List<GpioButtonConfig> buttons) {
    final Map<int, bool> lastState = {};

    debugPrint('GPIO: startuje gpioget polling na chipie $chipName');

    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      for (final cfg in buttons) {
        try {
          // Try v2 syntax first: gpioget --bias=pull-up <chip> <pin>
          var result = await Process.run(
            'gpioget',
            ['--bias=pull-up', chipName, cfg.pin.toString()],
          ).timeout(const Duration(seconds: 1));

          if (result.exitCode != 0) {
            // v1 syntax: gpioget <chip> <pin>
            result = await Process.run(
              'gpioget',
              [chipName, cfg.pin.toString()],
            ).timeout(const Duration(seconds: 1));
          }

          if (result.exitCode != 0) continue;

          final valueStr = result.stdout.toString().trim();
          final rawValue = int.tryParse(valueStr);
          if (rawValue == null) continue;

          final pressed = cfg.activeLow ? (rawValue == 0) : (rawValue == 1);
          final wasPressed = lastState[cfg.pin] ?? false;

          if (pressed && !wasPressed) {
            final now = DateTime.now();
            final lastAt = _lastPressAt[cfg.pin];
            if (lastAt == null || now.difference(lastAt) >= _debounce) {
              _lastPressAt[cfg.pin] = now;
              if (_logPresses) {
                debugPrint('GPIO press detected on pin ${cfg.pin} (gpioget)');
              }
              _invoke(cfg.onPressed);
            }
          }

          lastState[cfg.pin] = pressed;
        } catch (_) {}
      }
    });
  }

  void _invoke(GpioAction action) {
    try {
      final result = action();
      if (result is Future) {
        result.catchError((e, st) {
          debugPrint('GPIO action failed: $e\n$st');
        });
      }
    } catch (e, st) {
      debugPrint('GPIO action failed: $e\n$st');
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;

    for (final proc in _gpiomonProcesses) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _gpiomonProcesses.clear();
    _configs.clear();
    _lastPressAt.clear();
    _started = false;
  }
}

enum _GpiomonVersion { v2, v1, none }

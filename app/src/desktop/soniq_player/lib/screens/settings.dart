import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../remote_control_server.dart';
import '../audio_device_service.dart';
import '../i18n.dart';

class SettingsController extends ChangeNotifier {
  static const _keyHighContrast = 'isHighContrast';
  static const _keyLocale = 'currentLocale';
  static const _keyAudioDevice = 'selectedAudioDevice';
  static const _keyTextScale = 'textScaleFactor';
  static const _keyRemoteEnabled = 'remoteEnabled';
  static const _keyRemoteToken = 'remoteToken';
  static const _keySimpleControls = 'simpleControls';

  static const String _backlightPath = '/sys/class/backlight/10-0045/brightness';
  static const int _brightnessMin = 1;
  static const int _brightnessMax = 31;

  final AudioDeviceService _audioDeviceService = AudioDeviceService();

  bool _isHighContrast = false;
  double _textScale = 1.0;
  Locale _currentLocale = const Locale('en');
  bool _remoteEnabled = false;
  String? _remoteToken;
  bool _simpleControls = false;
  int _brightness = 16; // domyślny środek skali 1-31

  List<AudioDevice> _audioDevices = [];
  String? _selectedAudioDevice;

  bool get isHighContrast => _isHighContrast;
  double get textScale => _textScale;
  Locale get currentLocale => _currentLocale;
  bool get remoteEnabled => _remoteEnabled;
  String? get remoteToken => _remoteToken;
  bool get simpleControls => _simpleControls;
  int get brightness => _brightness;
  List<AudioDevice> get audioDevices => _audioDevices;
  String? get selectedAudioDevice => _selectedAudioDevice;

  SettingsController() {
    _loadSettings();
    _loadAudioDevices();
    _loadBrightness();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isHighContrast = prefs.getBool(_keyHighContrast) ?? false;
    _textScale = prefs.getDouble(_keyTextScale) ?? 1.0;
    _remoteEnabled = prefs.getBool(_keyRemoteEnabled) ?? false;
    _remoteToken = prefs.getString(_keyRemoteToken);
    _simpleControls = prefs.getBool(_keySimpleControls) ?? false;

    final localeTag = prefs.getString(_keyLocale);
    if (localeTag != null && localeTag.isNotEmpty) {
      final parts = localeTag.split('_');
      _currentLocale = Locale(parts.first, parts.length > 1 ? parts[1] : null);
    }

    _selectedAudioDevice = prefs.getString(_keyAudioDevice);
    notifyListeners();
  }

  Future<void> _loadAudioDevices() async {
    _audioDevices = await _audioDeviceService.getOutputDevices();

    if (_selectedAudioDevice != null) {
      final exists = _audioDevices.any((d) => d.name == _selectedAudioDevice);
      if (exists) {
        await _audioDeviceService.setOutputDevice(_selectedAudioDevice!);
      }
    }
    notifyListeners();
  }

  Future<void> refreshAudioDevices() => _loadAudioDevices();

  Future<void> toggleHighContrast(bool value) async {
    _isHighContrast = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHighContrast, value);
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    _textScale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTextScale, value);
    notifyListeners();
  }

  Future<void> setRemoteEnabled(bool value) async {
    _remoteEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemoteEnabled, value);
    notifyListeners();
  }

  Future<void> setRemoteToken(String? token) async {
    _remoteToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_keyRemoteToken);
    } else {
      await prefs.setString(_keyRemoteToken, token);
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _currentLocale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale.toLanguageTag());
    notifyListeners();
  }

  Future<void> toggleLanguage() async {
    final newLocale = _currentLocale.languageCode == 'pl'
        ? const Locale('en')
        : const Locale('pl');
    await setLocale(newLocale);
  }

  Future<void> setSimpleControls(bool value) async {
    _simpleControls = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySimpleControls, value);
    notifyListeners();
  }

  Future<void> setAudioDevice(String deviceName) async {
    _selectedAudioDevice = deviceName;
    await _audioDeviceService.setOutputDevice(deviceName);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioDevice, deviceName);

    notifyListeners();
  }

  Future<void> _loadBrightness() async {
    try {
      final f = File(_backlightPath);
      if (await f.exists()) {
        final raw = int.tryParse((await f.readAsString()).trim());
        if (raw != null) {
          _brightness = raw.clamp(_brightnessMin, _brightnessMax);
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> setBrightness(int value) async {
    final clamped = value.clamp(_brightnessMin, _brightnessMax);
    try {
      final f = File(_backlightPath);
      await f.writeAsString('$clamped');
      _brightness = clamped;
      notifyListeners();
    } catch (_) {}
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    const double iconSize = 36.0;
    const double fontSize = 22.0;
    final colorScheme = Theme.of(context).colorScheme;
    final remoteServer = RemoteControlServer.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                secondary: Icon(Icons.contrast, size: iconSize),
                title: Text(
                  strings.get('highContrast'),
                  style: const TextStyle(fontSize: fontSize),
                ),
                value: controller.isHighContrast,
                onChanged: (value) => controller.toggleHighContrast(value),
              );
            },
          ),
          const Divider(thickness: 2),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                secondary: Icon(Icons.language, size: iconSize),
                title: Text(
                  strings.get('language'),
                  style: const TextStyle(fontSize: fontSize),
                ),
                subtitle: Text(
                  strings.get('languageHint'),
                  style: const TextStyle(fontSize: 18),
                ),
                value: controller.currentLocale.languageCode == 'pl',
                onChanged: (value) => controller.toggleLanguage(),
              );
            },
          ),
          const Divider(thickness: 2),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.text_fields, size: iconSize),
                        const SizedBox(width: 16),
                        Text(
                          '${strings.get('fontSize')}: ${(controller.textScale * 100).round()}%',
                          style: const TextStyle(fontSize: fontSize),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: controller.textScale,
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    label: '${(controller.textScale * 100).round()}%',
                    onChanged: (value) => controller.setTextScale(value),
                  ),
                ],
              );
            },
          ),
          const Divider(thickness: 2),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                secondary: Icon(Icons.qr_code, size: iconSize),
                title: Text(
                  strings.get('remoteControl'),
                  style: const TextStyle(fontSize: fontSize),
                ),
                subtitle: Text(
                  strings.get('remoteHint'),
                  style: const TextStyle(fontSize: 18),
                ),
                value: controller.remoteEnabled,
                onChanged: (value) => controller.setRemoteEnabled(value),
              );
            },
          ),
          if (controller.remoteEnabled)
            ListenableBuilder(
              listenable: remoteServer,
              builder: (context, _) {
                final wsUrl = remoteServer.wsUrl;
                if (wsUrl == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(strings.get('startingServer')),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Center(
                          child: QrImageView(
                            data: wsUrl,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(strings.get('wsAddress'), style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      SelectableText(wsUrl, style: const TextStyle(fontSize: 16)),
                      if (remoteServer.wsUrlWithCode != null) ...[
                        const SizedBox(height: 8),
                        Text('${strings.get('wsAddress')} (code)', style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        SelectableText(remoteServer.wsUrlWithCode!, style: const TextStyle(fontSize: 16)),
                      ],
                      if (remoteServer.pairCode != null) ...[
                        const SizedBox(height: 12),
                        Text(strings.get('pairCode'), style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 4),
                        SelectableText(remoteServer.pairCode!, style: const TextStyle(fontSize: 22)),
                      ],
                    ],
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(strings.get('remoteDisabled')),
            ),
          const Divider(thickness: 2),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                secondary: Icon(Icons.text_snippet, size: iconSize),
                title: Text(
                  strings.get('simpleControls'),
                  style: const TextStyle(fontSize: fontSize),
                ),
                subtitle: Text(
                  strings.get('simpleControlsHint'),
                  style: const TextStyle(fontSize: 18),
                ),
                value: controller.simpleControls,
                onChanged: (value) => controller.setSimpleControls(value),
              );
            },
          ),
          const Divider(thickness: 2),
          if (controller.audioDevices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                strings.get('audioDevice'),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                return Column(
                  children: controller.audioDevices.map((device) {
                    final isSelected = device.name == controller.selectedAudioDevice;
                    return RadioListTile<String>(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                      title: Text(
                        device.description,
                        style: const TextStyle(fontSize: 20),
                      ),
                      value: device.name,
                      groupValue: controller.selectedAudioDevice,
                      onChanged: (value) {
                        if (value != null) {
                          controller.setAudioDevice(value);
                        }
                      },
                      secondary: Icon(
                        isSelected ? Icons.speaker : Icons.speaker_outlined,
                        size: iconSize,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
          const Divider(thickness: 2),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.brightness_6, size: iconSize),
                        const SizedBox(width: 16),
                        Text(
                          '${strings.get('brightness')}: ${controller.brightness}',
                          style: const TextStyle(fontSize: fontSize),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: controller.brightness.toDouble(),
                    min: 1,
                    max: 31,
                    divisions: 30,
                    label: '${controller.brightness}',
                    onChanged: (value) => controller.setBrightness(value.round()),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

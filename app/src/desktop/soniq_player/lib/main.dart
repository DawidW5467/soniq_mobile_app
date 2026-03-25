import 'dart:async';
import 'dart:io';
import 'dart:math'; // import math for visualizer painter
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'audio_controller.dart';
import 'remote_control_server.dart';
import 'screens/settings.dart';
import 'screens/tracks_screen.dart';
import 'playlists/playlists_controller.dart';
import 'playlists/playlists_screen.dart';
import 'screens/history_screen.dart';
import 'library/library_screen.dart';
import 'library/library_player_screen.dart';
import 'i18n.dart';
import 'cava_visualizer.dart';
import 'metadata/lyric_parser.dart';
import 'player_widgets.dart';
import 'gpio_buttons_service.dart';
import 'usb_drive_service.dart';

/// Globalny klucz nawigatora, aby moduły bez BuildContext (np. WebSocket) mogły otwierać ekrany.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

enum LastPlayerKind { none, music, library }

final ValueNotifier<LastPlayerKind> lastPlayerKind = ValueNotifier(LastPlayerKind.none);
final ValueNotifier<bool> isOnHomeMenu = ValueNotifier(true);

void setLastPlayerKind(LastPlayerKind kind) {
  if (lastPlayerKind.value != kind) {
    lastPlayerKind.value = kind;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SettingsController _settingsController = SettingsController();
  final RemoteControlServer _remoteServer = RemoteControlServer.instance;
  final AudioController _audioController = AudioController();

  @override
  void initState() {
    super.initState();
    _settingsController.addListener(_syncRemoteServer);
    _syncRemoteServer();
    _setupGpioButtons();
  }

  @override
  void dispose() {
    _settingsController.removeListener(_syncRemoteServer);
    GpioButtonsService.instance.dispose();
    super.dispose();
  }

  void _setupGpioButtons() {
    GpioButtonsService.instance.start(
      buttons: [
        GpioButtonConfig(pin: 23, onPressed: _handlePrev),
        GpioButtonConfig(pin: 18, onPressed: _handlePauseToggle),
        GpioButtonConfig(pin: 15, onPressed: _handleNext),
        GpioButtonConfig(pin: 14, onPressed: _handleToggleMenuOrLastPlayed),
      ],
      debounce: const Duration(milliseconds: 300),
      logPresses: true,
    );
  }

  Future<void> _handlePrev() async {
    await _audioController.previous();
  }

  Future<void> _handleNext() async {
    await _audioController.next();
  }

  Future<void> _handlePauseToggle() async {
    final isPlaying = _audioController.state.value.isPlaying;
    if (isPlaying) {
      await _audioController.pause();
    } else {
      await _audioController.play();
    }
  }

  Future<void> _handleToggleMenuOrLastPlayed() async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    if (!isOnHomeMenu.value) {
      nav.popUntil((route) => route.isFirst);
      isOnHomeMenu.value = true;
      return;
    }

    final kind = lastPlayerKind.value;
    if (kind == LastPlayerKind.none) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      final t = AppStrings.of(ctx);
      final messenger = ScaffoldMessenger.maybeOf(ctx);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text(t.get('noLastPlayed'))),
      );
      return;
    }

    if (kind == LastPlayerKind.library) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      final t = AppStrings.of(ctx);
      await nav.push(
        MaterialPageRoute(
          builder: (_) => LibraryPlayerScreen(
            title: t.get('lastPlayed'),
            settingsController: _settingsController,
          ),
        ),
      );
      return;
    }

    await nav.push(
      MaterialPageRoute(
        builder: (_) => MusicPlayerScreen(
          settingsController: _settingsController,
        ),
      ),
    );
  }

  Future<void> _syncRemoteServer() async {
    if (_settingsController.remoteEnabled) {
      await _remoteServer.start(token: _settingsController.remoteToken);
      if (_remoteServer.token != _settingsController.remoteToken) {
        await _settingsController.setRemoteToken(_remoteServer.token);
      }
    } else {
      await _remoteServer.stop();
    }
  }

  ColorScheme _vintageColorScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFC26D3A),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE4B186),
      onPrimaryContainer: Color(0xFF3D1E0E),
      secondary: Color(0xFF6F7B4B),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFB9C08D),
      onSecondaryContainer: Color(0xFF2E3318),
      tertiary: Color(0xFF4F6E6B),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFB3D4CF),
      onTertiaryContainer: Color(0xFF203532),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: Color(0xFFF4E8D4),
      onSurface: Color(0xFF514636),
      surfaceContainerHighest: Color(0xFFD8CCB8),
      outline: Color(0xFF8A7C69),
      outlineVariant: Color(0xFFC9B9A3),
      shadow: Color(0xFF000000),
      scrim: Color(0x88000000),
      inverseSurface: Color(0xFF3A3024),
      onInverseSurface: Color(0xFFE7DAC8),
      inversePrimary: Color(0xFF8E4719),
      surfaceTint: Color(0xFFC26D3A),
    );
  }

  ColorScheme _highContrastColorScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFFF00),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFFFFFF00),
      onPrimaryContainer: Color(0xFF000000),
      secondary: Color(0xFFFFFF00),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFFFFFF00),
      onSecondaryContainer: Color(0xFF000000),
      tertiary: Color(0xFFFFFF00),
      onTertiary: Color(0xFF000000),
      tertiaryContainer: Color(0xFFFFFF00),
      onTertiaryContainer: Color(0xFF000000),
      error: Color(0xFFCF6679),
      onError: Color(0xFF000000),
      errorContainer: Color(0xFFB00020),
      onErrorContainer: Color(0xFFFFFFFF),
      surface: Color(0xFF000000),
      onSurface: Color(0xFFFFFF00),
      surfaceContainerHighest: Color(0xFF333333),
      onSurfaceVariant: Color(0xFFFFFF00),
      outline: Color(0xFFFFFF00),
      outlineVariant: Color(0xFFFFFF00),
      shadow: Color(0xFFFFFF00),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF000000),
      onInverseSurface: Color(0xFFFFFF00),
      inversePrimary: Color(0xFF000000),
      surfaceTint: Color(0xFFFFFF00),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settingsController,
      builder: (context, child) {
        final colorScheme = _settingsController.isHighContrast
            ? _highContrastColorScheme()
            : _vintageColorScheme();

        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'Soniq',
          scrollBehavior: const TouchFriendlyScrollBehavior(),
          // Make app locale follow settings (fix: PL switch actually changes UI)
          locale: _settingsController.currentLocale,
          supportedLocales: const [
            Locale('en'),
            Locale('pl'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supported) {
            final chosen = _settingsController.currentLocale;
            for (final l in supported) {
              if (l.languageCode == chosen.languageCode) return l;
            }
            return supported.first;
          },
          theme: ThemeData(
            colorScheme: colorScheme,
            useMaterial3: true,
            scaffoldBackgroundColor: colorScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: colorScheme.inversePrimary,
              foregroundColor: colorScheme.onInverseSurface,
              elevation: 0,
            ),
            iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
            sliderTheme: SliderThemeData(
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.45),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(_settingsController.textScale),
              ),
              child: child!,
            );
          },
          home: MusicSourcesScreen(settingsController: _settingsController),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

/// Model źródła muzyki
class MusicSource {
  final String name;
  final String path;
  final IconData icon;
  final Color? color;
  final bool isPlaylistShortcut;
  final bool isLastPlayedShortcut;

  const MusicSource({
    required this.name,
    required this.path,
    required this.icon,
    this.color,
    this.isPlaylistShortcut = false,
    this.isLastPlayedShortcut = false,
  });
}

/// Ekran startowy z kafelkami źródeł muzyki
class MusicSourcesScreen extends StatefulWidget {
  final SettingsController? settingsController;

  const MusicSourcesScreen({super.key, this.settingsController});

  @override
  State<MusicSourcesScreen> createState() => _MusicSourcesScreenState();
}

class _MusicSourcesScreenState extends State<MusicSourcesScreen> {
  late List<MusicSource> _sources;
  Timer? _availabilityTimer;
  final Map<String, bool> _availabilityCache = {};
  bool _isOpeningCd = false;
  List<UsbDriveInfo> _usbDrives = const [];

  @override
  void initState() {
    super.initState();
    isOnHomeMenu.value = true;
    _usbDrives = UsbDriveService.scan();
    _sources = _buildSources();
    _refreshAvailability();
    lastPlayerKind.addListener(_handleLastPlayerChanged);
    _availabilityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshAvailability();
    });
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    lastPlayerKind.removeListener(_handleLastPlayerChanged);
    super.dispose();
  }

  void _handleLastPlayerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  List<MusicSource> _buildSources() {
    final home = Platform.environment['HOME'] ?? '';

    final musicCandidates = [
      if (home.isNotEmpty) p.join(home, 'Music'),
      if (home.isNotEmpty) p.join(home, 'Muzyka'),
    ];
    final downloadsMusicCandidates = [
      if (home.isNotEmpty) p.join(home, 'Downloads', 'Music'),
      if (home.isNotEmpty) p.join(home, 'Pobrane', 'Muzyka'),
    ];

    String firstExisting(List<String> cands) {
      for (final c in cands) {
        if (c.isNotEmpty && Directory(c).existsSync()) return c;
      }
      return cands.isNotEmpty ? cands.first : '';
    }

    final usbSources = _usbDrives.map((drive) {
      return MusicSource(
        name: 'usb:${drive.label}',
        path: drive.path,
        icon: Icons.usb,
        color: const Color(0xFF8E4719),
      );
    });

    return [
      MusicSource(
        name: 'last_played',
        path: '',
        icon: Icons.play_circle_fill,
        color: const Color(0xFF6F7B4B),
        isLastPlayedShortcut: true,
      ),
      MusicSource(
        name: 'favorites',
        path: '',
        icon: Icons.favorite,
        color: const Color(0xFFC26D3A),
        isPlaylistShortcut: true,
      ),
      MusicSource(
        name: 'playlists',
        path: '',
        icon: Icons.playlist_play,
        color: const Color(0xFF4F6E6B),
        isPlaylistShortcut: true,
      ),
      MusicSource(
        name: 'music',
        path: firstExisting(musicCandidates),
        icon: Icons.folder_special,
        color: const Color(0xFF6F7B4B),
      ),
      MusicSource(
        name: 'downloads',
        path: firstExisting(downloadsMusicCandidates),
        icon: Icons.download,
        color: const Color(0xFF4F6E6B),
      ),
      MusicSource(
        name: 'cd',
        path: '/run/user/1000/gvfs/cdda:host=sr0',
        icon: Icons.album,
        color: const Color(0xFFC26D3A),
      ),
      ...usbSources,
      MusicSource(
        name: 'network',
        path: '/media/share/Media/Music',
        icon: Icons.cloud,
        color: const Color(0xFF6F7B4B),
      ),
      MusicSource(
        name: 'local',
        path: '/mnt/music',
        icon: Icons.folder,
        color: const Color(0xFF4F6E6B),
      ),
      MusicSource(
        name: 'library_all',
        path: '',
        icon: Icons.local_library,
        color: const Color(0xFF6F7B4B),
        isPlaylistShortcut: true,
      ),
    ];
  }

  /// Sprawdza czy źródło jest dostępne (katalog istnieje i ma pliki muzyczne)
  Future<bool> _isSourceAvailable(MusicSource source) async {
    if (source.isLastPlayedShortcut) {
      return lastPlayerKind.value != LastPlayerKind.none;
    }
    if (source.name == 'favorites') {
      return AudioController().likedPaths.value.isNotEmpty;
    }
    if (source.isPlaylistShortcut) return true;
    if (source.path.isEmpty) return false;
    try {
      final dir = Directory(source.path);
      if (!await dir.exists()) return false;

      // Sprawdź czy są jakieś pliki muzyczne
      final allowed = {'.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'};
      final hasMusic = await dir
          .list(followLinks: false)
          .any((entity) {
            if (entity is File) {
              return allowed.contains(p.extension(entity.path).toLowerCase());
            }
            return false;
          });
      return hasMusic;
    } catch (_) {
      return false;
    }
  }

  void _openLastPlayed() {
    if (!mounted) return;
    final kind = lastPlayerKind.value;
    if (kind == LastPlayerKind.none) return;
    final strings = AppStrings.of(context);
    if (kind == LastPlayerKind.library) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryPlayerScreen(
            title: strings.get('lastPlayed'),
            settingsController: widget.settingsController,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerScreen(
          settingsController: widget.settingsController,
        ),
      ),
    );
  }

  void openMusicSource(MusicSource source) async {
    if (!source.isLastPlayedShortcut) {
      await AudioController().stop();
    }
    if (source.isLastPlayedShortcut) {
      _openLastPlayed();
      return;
    }
    if (source.name == 'favorites') {
      final audio = AudioController();
      final liked = audio.likedPaths.value.toList();
      if (liked.isEmpty) {
        if (!mounted) return;
        final t = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.get('noFavorites'))),
        );
        return;
      }
      await audio.loadPlaylist(liked, startIndex: 0, fromUserPlaylist: true);
      await audio.play();
      if (!mounted) return;
      final t = AppStrings.of(context);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryPlayerScreen(
            title: t.get('favorites'),
            settingsController: widget.settingsController,
          ),
        ),
      );
      return;
    }
    if (source.isPlaylistShortcut && source.name == 'playlists') {
      if (!mounted) return;
      final sc = widget.settingsController;
      if (sc == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistsScreen(
            playlistsController: PlaylistsController.instance,
            settingsController: sc,
          ),
        ),
      );
      return;
    }

    if (source.name == 'library_all') {
      final sources = <String, String>{};
      for (final s in _sources) {
        if (s.path.isEmpty) continue;
        if (s.name == 'library_all') continue;
        if (s.isPlaylistShortcut) continue;
        sources['${s.name}:${p.basename(s.path)}'] = s.path;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryScreen(
            sources: sources,
            settingsController: widget.settingsController,
          ),
        ),
      );
      return;
    }

    final isCdda = source.path.contains('cdda') || source.path.contains('gvfs/cdda') || source.name == 'cd';
    if (isCdda && mounted) {
      setState(() => _isOpeningCd = true);
    }

    try {
      // Wejście w zwykłe źródło/katalog powinno zawsze wyjść z trybu playlisty użytkownika.
      AudioController().resetPlaylistMode();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MusicPlayerScreen(
            initialDirectory: source.path,
            settingsController: widget.settingsController,
          ),
        ),
      );
    } finally {
      if (isCdda && mounted) {
        setState(() => _isOpeningCd = false);
      }
    }
  }

  Future<void> _refreshAvailability() async {
    final newUsb = UsbDriveService.scan();
    if (!usbListsEqual(_usbDrives, newUsb)) {
      _usbDrives = newUsb;
      _sources = _buildSources();
      _availabilityCache.clear();
    }

    var changed = false;
    for (final source in _sources) {
      final key = sourceKey(source);
      final available = await _isSourceAvailable(source);
      if (_availabilityCache[key] != available) {
        _availabilityCache[key] = available;
        changed = true;
      }
    }
    if ((changed || _availabilityCache.isNotEmpty) && mounted) {
      setState(() {});
    }
  }

  bool usbListsEqual(List<UsbDriveInfo> a, List<UsbDriveInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].label != b[i].label) return false;
    }
    return true;
  }

  String sourceKey(MusicSource source) => '${source.name}|${source.path}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('appTitle')),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.settingsController?.simpleControls == true)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: () {
                if (widget.settingsController != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(controller: widget.settingsController!),
                    ),
                  );
                }
              },
              child: Text(strings.get('settings')),
            )
          else
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: strings.get('settings'),
              onPressed: () {
                if (widget.settingsController != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(controller: widget.settingsController!),
                    ),
                  );
                }
              },
            ),
          if (widget.settingsController != null)
            ListenableBuilder(
              listenable: widget.settingsController!,
              builder: (context, _) {
                final devices = widget.settingsController!.audioDevices;
                if (devices.isEmpty) return const SizedBox.shrink();

                final simple = widget.settingsController?.simpleControls == true;
                return PopupMenuButton<String>(
                  icon: simple ? null : const Icon(Icons.speaker),
                  tooltip: strings.get('audioOutput'),
                  child: simple
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            strings.get('audioOutput'),
                            style: TextStyle(
                              color: Theme.of(context).appBarTheme.foregroundColor,
                            ),
                          ),
                        )
                      : null,
                  onSelected: (String deviceName) {
                    widget.settingsController!.setAudioDevice(deviceName);
                  },
                  itemBuilder: (BuildContext context) {
                    return devices.map((device) {
                      final isSelected = device.name == widget.settingsController!.selectedAudioDevice;
                      return PopupMenuItem<String>(
                        value: device.name,
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check : Icons.speaker_group_outlined,
                              color: isSelected ? colorScheme.primary : null,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                device.description,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? colorScheme.primary : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ScrollConfiguration(
              behavior: const TouchFriendlyScrollBehavior(),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                itemCount: _sources.length,
                itemBuilder: (context, index) {
                  final source = _sources[index];
                  final key = sourceKey(source);
                  final isLastPlayed = source.isLastPlayedShortcut;
                  final isAvailable = isLastPlayed
                      ? lastPlayerKind.value != LastPlayerKind.none
                      : (_availabilityCache[key] ?? false);
                  final isLoading = _availabilityCache.containsKey(key) ? false : false;

                  final displayName = source.isLastPlayedShortcut
                      ? strings.get('lastPlayed')
                      : source.name == 'favorites'
                          ? strings.get('favorites')
                          : source.name == 'library_all'
                              ? strings.get('library_all')
                              : source.isPlaylistShortcut
                                  ? strings.get('playlists')
                                  : source.name.startsWith('usb:')
                                      ? 'USB ${source.name.substring(4)}'
                                      : strings.get(source.name);

                  return _MusicSourceTile(
                    source: source,
                    displayName: displayName,
                    isAvailable: isAvailable,
                    isLoading: isLoading,
                    onTap: isAvailable ? () => openMusicSource(source) : null,
                  );
                },
              ),
            ),
          ),
          if (_isOpeningCd)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        strings.get('loadingCd'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kafelek pojedynczego źródła muzyki
class _MusicSourceTile extends StatelessWidget {
  const _MusicSourceTile({
    required this.source,
    required this.displayName,
    required this.isAvailable,
    required this.isLoading,
    this.onTap,
  });

  final MusicSource source;
  final String displayName;
  final bool isAvailable;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isHighContrast = colorScheme.brightness == Brightness.dark;

    final tileColor = isHighContrast
        ? colorScheme.primary
        : (source.color ?? colorScheme.primaryContainer);

    final contentColor = isHighContrast ? Colors.black : Colors.white;

    return Card(
      elevation: isAvailable ? 6 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isAvailable
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tileColor.withValues(alpha: 0.8),
                      tileColor.withValues(alpha: 0.95),
                    ],
                  )
                : null,
            color: isAvailable ? null : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: isHighContrast ? contentColor : colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Icon(
                        source.icon,
                        size: 80,
                        color: isAvailable
                            ? contentColor.withValues(alpha: 0.95)
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: isAvailable
                              ? contentColor
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isAvailable && !isLoading)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 24,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({
    super.key,
    this.initialDirectory,
    this.settingsController,
  });

  final String? initialDirectory;
  final SettingsController? settingsController;

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioController audioController = AudioController();
  final CavaController cava = CavaController();
  bool showLyrics = false;
  bool showVisualizerInsteadOfCover = false;
  double? seekPosition;
  bool isLoadingCd = false;
  final Set<String> metadataWarmup = <String>{};
  String? _lastMetaSyncPath;
  String? _lastMetaSyncLyrics;

  final List<String> predefinedDirs = [];
  String? selectedDir;
  List<File> files0 = [];
  Timer? refreshTimer;
  bool isRefreshingDir = false;

  StreamSubscription<int?>? playlistIndexSub;

  static const double swipeMinVelocity = 650.0;

  Future<void> togglePlayPause(AudioState audioState) async {
    if (audioState.isPlaying) {
      await audioController.pause();
    } else {
      await audioController.play();
    }
  }

  void openTrackList() {
    if (!mounted) return;
    if (selectedDir == null || files0.isEmpty || widget.settingsController == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TracksScreen(
          settingsController: widget.settingsController!,
          directory: selectedDir!,
          files: files0,
          playlistsController: PlaylistsController.instance,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    isOnHomeMenu.value = false;
    setLastPlayerKind(LastPlayerKind.music);

    if (!audioController.isInitialized) {
      audioController.init();
    }

    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      if (home.isNotEmpty) p.join(home, 'Music'),
      if (home.isNotEmpty) p.join(home, 'Muzyka'),
      if (home.isNotEmpty) p.join(home, 'Downloads', 'Music'),
      if (home.isNotEmpty) p.join(home, 'Pobrane', 'Muzyka'),
      '/mnt/music',
      '/media/share/Media/Music',
      '/run/user/1000/gvfs/cdda:host=sr0',
    ];

    final usbDirs = UsbDriveService.scan().map((d) => d.path);

    predefinedDirs
      ..clear()
      ..addAll({...candidates, ...usbDirs});

    if (audioController.playlist.isNotEmpty) {
      restorePlaylistState(callSetState: false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialDirectory != null) {
        audioController.resetPlaylistMode();
        selectDirectory(widget.initialDirectory!, suppressSnackBars: true);
        return;
      }
      if (audioController.isPlaylistMode) return;
      if (audioController.playlist.isEmpty) {
        final dirToLoad = predefinedDirs.firstWhere(
          (d) => Directory(d).existsSync(),
          orElse: () => '',
        );
        if (dirToLoad.isNotEmpty) {
          selectDirectory(dirToLoad, suppressSnackBars: true);
        }
      }
    });

    playlistIndexSub?.cancel();
    playlistIndexSub = audioController.currentIndexStream.listen((_) {
      if (!mounted) return;
      restorePlaylistState(callSetState: true);
    });

    refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshSelectedDirectory();
    });

    if (audioController.state.value.isPlaying) {
      cava.start();
    }

    audioController.state.addListener(onAudioStateChanged);

    updateCurrentMeta();
    audioController.state.addListener(handleMetaSync);
    RemoteControlServer.instance.addListener(_syncRemoteOverlayState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRemoteOverlayState());
  }

  void onAudioStateChanged() {
    if (audioController.state.value.isPlaying) {
      cava.start();
    } else {
      cava.stop();
    }
  }

  @override
  void dispose() {
    audioController.state.removeListener(handleMetaSync);
    audioController.state.removeListener(onAudioStateChanged);
    cava.stop();
    refreshTimer?.cancel();
    playlistIndexSub?.cancel();
    RemoteControlServer.instance.removeListener(_syncRemoteOverlayState);
    super.dispose();
  }

  void restorePlaylistState({bool callSetState = true}) {
    // Gdy playlista pochodzi z WebSocket/biblioteki/playlist (isPlaylistMode),
    // nie nadpisuj files0 ani selectedDir — MusicPlayerScreen zachowuje swoje źródło.
    if (audioController.isPlaylistMode) return;

    void updateState() {
      files0 = audioController.playlist.map((path) => File(path)).toList();
      if (files0.isNotEmpty) {
        final dir = p.dirname(files0.first.path);
        selectedDir = dir.endsWith('/') && dir.length > 1
            ? dir.substring(0, dir.length - 1)
            : dir;
      }
    }

    if (callSetState) {
      setState(updateState);
    } else {
      updateState();
    }
  }

  List<File> listAudioFiles(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return [];
      final allowed = {
        '.mp3',
        '.flac',
        '.wav',
        '.m4a',
        '.ogg',
        '.aac',
      };
      final files = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => allowed.contains(p.extension(f.path).toLowerCase()))
          .toList();
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      return files;
    } catch (_) {
      return [];
    }
  }

  Future<void> selectDirectory(String path, {bool suppressSnackBars = false}) async {
    final normalizedPath = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final normalizedSelectedDir = selectedDir?.endsWith('/') == true && selectedDir!.length > 1
        ? selectedDir!.substring(0, selectedDir!.length - 1)
        : selectedDir;

    if (normalizedSelectedDir == normalizedPath &&
        files0.isNotEmpty &&
        audioController.playlist.isNotEmpty) {
      return;
    }

    final isCdda = normalizedPath.contains('cdda') || normalizedPath.contains('gvfs/cdda');
    if (isCdda) {
      setState(() => isLoadingCd = true);
    }

    try {
      if (isCdda && mounted && !suppressSnackBars) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final t = AppStrings.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t.get('loadingCdLong')),
              duration: const Duration(seconds: 2),
            ),
          );
        });
      }

      final files = listAudioFiles(normalizedPath);
      setState(() {
        selectedDir = normalizedPath;
        files0 = files;
      });
      if (files.isNotEmpty) {
        // Jawny wybór katalogu przez użytkownika — wyłącz tryb playlisty,
        // aby loadPlaylist nie zignorowało nowych plików.
        audioController.resetPlaylistMode();
        await audioController.loadPlaylist(files.map((f) => f.path).toList());

        if (isCdda && mounted && !suppressSnackBars) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final t = AppStrings.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t.get('cdLoaded')),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          });
        }
      }
    } finally {
      if (isCdda && mounted) {
        setState(() => isLoadingCd = false);
      }
    }
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> refreshSelectedDirectory() async {
    if (audioController.isPlaylistMode) return;
    if (isRefreshingDir) return;
    final dir = selectedDir;
    if (dir == null || dir.isEmpty) {
      await audioController.refreshMetadataForPlaylist();
      return;
    }
    isRefreshingDir = true;
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) {
        await audioController.clearPlaylist();
        if (mounted) {
          setState(() {
            files0 = [];
            selectedDir = null;
          });
        }
        return;
      }

      final newFiles = listAudioFiles(dir);
      final oldPaths = files0.map((f) => f.path).toList();
      final newPaths = newFiles.map((f) => f.path).toList();
      if (!listEquals(oldPaths, newPaths)) {
        final currentPath = (audioController.currentIndex >= 0 && audioController.currentIndex < oldPaths.length)
            ? oldPaths[audioController.currentIndex]
            : null;
        var startIndex = 0;
        if (currentPath != null) {
          final idx = newPaths.indexOf(currentPath);
          if (idx >= 0) startIndex = idx;
        }
        await audioController.loadPlaylist(newPaths, startIndex: startIndex);
        if (mounted) {
          setState(() {
            files0 = newFiles;
          });
        }
      }
      await audioController.refreshMetadataForPlaylist();
    } finally {
      isRefreshingDir = false;
    }
  }

  bool listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  AudioMetadata? currentMeta;

  String? _currentPlaylistPath([int? explicitIndex]) {
    final playlist = audioController.playlist;
    if (playlist.isEmpty) return null;
    final idx = (explicitIndex ?? audioController.currentIndex).clamp(0, playlist.length - 1);
    return playlist[idx];
  }

  void updateCurrentMeta() {
    final path = _currentPlaylistPath();
    if (path == null) {
      currentMeta = null;
      return;
    }
    currentMeta = audioController.metadataForPath(path);
  }

  void handleMetaSync() {
    final path = _currentPlaylistPath();
    final prevPath = _lastMetaSyncPath;
    final prevLyrics = _lastMetaSyncLyrics;

    updateCurrentMeta();
    final nextLyrics = currentMeta?.lyrics;

    final trackChanged = path != prevPath;
    final lyricsChanged = nextLyrics != prevLyrics;

    _lastMetaSyncPath = path;
    _lastMetaSyncLyrics = nextLyrics;

    if (mounted && (trackChanged || lyricsChanged)) {
      setState(() {});
    }
    if (trackChanged) {
      _syncRemoteOverlayState();
    }
  }

  void ensureMetadataLoaded(String path) {
    if (metadataWarmup.contains(path)) return;
    metadataWarmup.add(path);
    audioController.getMetadata(path).then((_) {
      if (!mounted) return;
      setState(() {});
    }).whenComplete(() {
      metadataWarmup.remove(path);
    });
  }

  void _syncRemoteOverlayState() {
    final remote = RemoteControlServer.instance;
    final nextVisualizer = remote.showVisualizer;
    final nextLyrics = remote.showLyrics;
    var needsImmediateSetState = false;

    if (showVisualizerInsteadOfCover != nextVisualizer) {
      showVisualizerInsteadOfCover = nextVisualizer;
      needsImmediateSetState = true;
    }

    if (!nextLyrics) {
      if (showLyrics) {
        showLyrics = false;
        needsImmediateSetState = true;
      }
      if (mounted && needsImmediateSetState) setState(() {});
      return;
    }

    final path = _currentPlaylistPath();
    if (path == null) {
      if (showLyrics != false) {
        showLyrics = false;
        if (mounted) setState(() {});
      } else if (mounted && needsImmediateSetState) {
        setState(() {});
      }
      return;
    }

    audioController.getMetadata(path).then((meta) {
      if (!mounted) return;
      final hasLyrics = meta.lyrics != null && meta.lyrics!.trim().isNotEmpty;
      final resolvedLyrics = nextLyrics && hasLyrics;
      if (showLyrics != resolvedLyrics || showVisualizerInsteadOfCover != nextVisualizer) {
        setState(() {
          showLyrics = resolvedLyrics;
          showVisualizerInsteadOfCover = nextVisualizer;
        });
      } else if (needsImmediateSetState) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('appTitle')),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.settingsController?.simpleControls == true)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: () {
                if (widget.settingsController != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(controller: widget.settingsController!),
                    ),
                  );
                }
              },
              child: Text(strings.get('settings')),
            )
          else
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: strings.get('settings'),
              onPressed: () {
                if (widget.settingsController != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(controller: widget.settingsController!),
                    ),
                  );
                }
              },
            ),
          if (widget.settingsController != null)
            ListenableBuilder(
              listenable: widget.settingsController!,
              builder: (context, _) {
                final devices = widget.settingsController!.audioDevices;
                if (devices.isEmpty) return const SizedBox.shrink();

                final simple = widget.settingsController?.simpleControls == true;
                return PopupMenuButton<String>(
                  icon: simple ? null : const Icon(Icons.speaker),
                  tooltip: strings.get('audioOutput'),
                  child: simple
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            strings.get('audioOutput'),
                            style: TextStyle(
                              color: Theme.of(context).appBarTheme.foregroundColor,
                            ),
                          ),
                        )
                      : null,
                  onSelected: (String deviceName) {
                    widget.settingsController!.setAudioDevice(deviceName);
                  },
                  itemBuilder: (BuildContext context) {
                    return devices.map((device) {
                      final isSelected = device.name == widget.settingsController!.selectedAudioDevice;
                      return PopupMenuItem<String>(
                        value: device.name,
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check : Icons.speaker_group_outlined,
                              color: isSelected ? colorScheme.primary : null,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                device.description,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? colorScheme.primary : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ValueListenableBuilder<AudioState>(
              valueListenable: audioController.state,
              builder: (context, audioState, _) {
                final position = audioState.position;

                String currentTitle;
                if (files0.isEmpty) {
                  currentTitle = strings.get('songTitleFallback');
                } else {
                  final idx = audioState.currentIndex.clamp(0, files0.length - 1);
                  currentTitle = audioState.currentTitle?.trim().isNotEmpty == true
                      ? audioState.currentTitle!.trim()
                      : p.basename(files0[idx].path);
                }

                final topSection = Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final size = constraints.maxWidth < constraints.maxHeight
                                    ? constraints.maxWidth
                                    : constraints.maxHeight;
                                final effectiveSize = size > 600 ? 600.0 : size;

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => togglePlayPause(audioState),
                                  onLongPress: openTrackList,
                                  onHorizontalDragEnd: (details) {
                                    final v = details.primaryVelocity ?? 0;
                                    if (v.abs() < swipeMinVelocity) return;
                                    if (v > 0) {
                                      audioController.previous();
                                    } else {
                                      audioController.next();
                                    }
                                  },
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (showVisualizerInsteadOfCover)
                                          SizedBox(
                                            width: effectiveSize + 90,
                                            height: effectiveSize + 90,
                                            child: IgnorePointer(
                                              child: Opacity(
                                                opacity: 1.0,
                                                child: _CavaVisualizerPainter(
                                                  stream: cava.dataStream,
                                                  color: colorScheme.brightness == Brightness.dark
                                                      ? const Color(0xFFFFFF00)
                                                      : colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (showVisualizerInsteadOfCover) ...[
                                          SizedBox(
                                            width: effectiveSize,
                                            height: effectiveSize,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Colors.transparent,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: ColoredBox(
                                                  color: Colors.transparent,
                                                  child: Center(
                                                    child: _CavaVisualizerPainter(
                                                      stream: cava.dataStream,
                                                      color: colorScheme.brightness == Brightness.dark
                                                          ? const Color(0xFFFFFF00)
                                                          : colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          Container(
                                            width: effectiveSize,
                                            height: effectiveSize,
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.1),
                                                  spreadRadius: 2,
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: Builder(builder: (context) {
                                              if (files0.isEmpty) {
                                                return Icon(
                                                  Icons.music_note,
                                                  size: effectiveSize * 0.5,
                                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                                );
                                              }

                                              final idx = audioState.currentIndex.clamp(0, files0.length - 1);
                                              final path = files0[idx].path;
                                              final meta = audioController.metadataForPath(path);

                                              if (meta == null) {
                                                ensureMetadataLoaded(path);
                                              }

                                              Widget artWidget;
                                              if (meta?.coverBytes != null && meta!.coverBytes!.isNotEmpty) {
                                                artWidget = Image.memory(meta.coverBytes!, fit: BoxFit.cover);
                                              } else if (meta?.coverPath != null) {
                                                artWidget = Image.file(File(meta!.coverPath!), fit: BoxFit.cover);
                                              } else {
                                                artWidget = Icon(
                                                  Icons.music_note,
                                                  size: effectiveSize * 0.5,
                                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                                );
                                              }

                                              if (colorScheme.brightness == Brightness.dark) {
                                                return ColorFiltered(
                                                  colorFilter: const ColorFilter.matrix(<double>[
                                                    0.2126, 0.7152, 0.0722, 0, 0,
                                                    0.2126, 0.7152, 0.0722, 0, 0,
                                                    0.2126, 0.7152, 0.0722, 0, 0,
                                                    0,      0,      0,      1, 0,
                                                  ]),
                                                  child: artWidget,
                                                );
                                              }
                                              return artWidget;
                                            }),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16.0, top: 16.0, bottom: 16.0),
                            child: showLyrics
                                ? _LyricsView(
                                    lyrics: files0.isNotEmpty
                                        ? (audioController.metadataForPath(
                                                files0[audioState.currentIndex.clamp(0, files0.length - 1)].path)
                                            ?.lyrics ?? '')
                                        : '',
                                    position: position,
                                    onClose: () {
                                      setState(() => showLyrics = false);
                                      unawaited(RemoteControlServer.instance.setRemoteLyrics(false));
                                    },
                                    textColor: colorScheme.onSurface,
                                    activeColor: colorScheme.primary,
                                    onSeek: (time) => audioController.seek(time),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          currentTitle,
                                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          audioState.album?.trim().isNotEmpty == true
                                              ? audioState.album!
                                              : (audioState.currentTitle != null ? strings.get('unknownAlbum') : ''),
                                          style: TextStyle(fontSize: 36, color: colorScheme.onSurfaceVariant),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          audioState.artist?.trim().isNotEmpty == true
                                              ? audioState.artist!
                                              : (selectedDir ?? strings.get('unknownArtist')),
                                          style: TextStyle(fontSize: 32, color: colorScheme.onSurfaceVariant),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                final currentPath = files0.isNotEmpty
                    ? files0[audioState.currentIndex.clamp(0, files0.length - 1)].path
                    : null;

                final controlsPanel = PlayerControlsPanel(
                  audio: audioController,
                  audioState: audioState,
                  settingsController: widget.settingsController,
                  strings: strings,
                  canOpenTrackList: selectedDir != null && files0.isNotEmpty,
                  currentTrackPath: currentPath,
                  onGoHome: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    isOnHomeMenu.value = true;
                  },
                  onOpenTrackList: openTrackList,
                  onOpenHistory: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen()));
                  },
                  onToggleVisualizer: () {
                    final next = !showVisualizerInsteadOfCover;
                    setState(() => showVisualizerInsteadOfCover = next);
                    unawaited(RemoteControlServer.instance.setRemoteVisualizer(next));
                  },
                  onToggleLyrics: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final noLyricsText = AppStrings.of(context).get('noLyrics');
                    if (showLyrics) {
                      setState(() => showLyrics = false);
                      await RemoteControlServer.instance.setRemoteLyrics(false);
                      return;
                    }
                    if (files0.isEmpty) {
                      await RemoteControlServer.instance.setRemoteLyrics(true);
                      return;
                    }
                    final idx = audioState.currentIndex.clamp(0, files0.length - 1);
                    final path = files0[idx].path;
                    final meta = await audioController.getMetadata(path);
                    if (!mounted) return;
                    final hasLyrics = meta.lyrics != null && meta.lyrics!.trim().isNotEmpty;
                    await RemoteControlServer.instance.setRemoteLyrics(true);
                    if (!mounted) return;
                    if (hasLyrics) {
                      setState(() => showLyrics = true);
                    } else {
                      messenger?.hideCurrentSnackBar();
                      messenger?.showSnackBar(
                        SnackBar(content: Text(noLyricsText)),
                      );
                    }
                  },
                );

                return Column(
                  children: [
                    topSection,
                    controlsPanel,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TouchFriendlyScrollBehavior extends MaterialScrollBehavior {
  const TouchFriendlyScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}

class _LyricsView extends StatelessWidget {
  const _LyricsView({
    required this.lyrics,
    required this.position,
    required this.onClose,
    required this.textColor,
    required this.activeColor,
    required this.onSeek,
  });

  final String lyrics;
  final Duration position;
  final VoidCallback onClose;
  final Color textColor;
  final Color activeColor;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No lyrics found', style: TextStyle(fontSize: 24, color: textColor)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      );
    }

    final parsed = LyricParser.parse(lyrics);
    final isSynced = parsed.isNotEmpty;

    if (!isSynced) {
      // Unsynced lyrics: just scrollable text
      return Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 60, 40, 100),
            child: Center(
              child: Text(
                lyrics,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, height: 1.6, color: textColor),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, size: 32),
              onPressed: onClose,
            ),
          ),
        ],
      );
    }

    // Synced Lyrics
    // Find current line index
    int activeIndex = -1;
    for (int i = 0; i < parsed.length; i++) {
        if (position >= parsed[i].time) {
            activeIndex = i;
        } else {
            break;
        }
    }

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Simple auto-scroll implementation using ScrollController and item height estimation
            // Ideally, use scrollable_positioned_list, but let's do a simple centered list view.

            // We want the active line to be roughly in the center.
            // Using a ListView with a controller that we animate.
            // Since this is stateless & rebuilt on position change, we might need a Stateful wrapper
            // to hold the ScrollController if we want smooth animation,
            // but standard ListView.builder works if we just rely on user scroll or crude jumps.
            // Let's use a specialized widget for smooth scrolling synced lyrics.
            return _SyncedLyricsList(
                lines: parsed,
                activeIndex: activeIndex,
                textColor: textColor,
                activeColor: activeColor,
                onSeek: onSeek,
            );
          },
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, size: 32),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

class _SyncedLyricsList extends StatefulWidget {
  const _SyncedLyricsList({
    required this.lines,
    required this.activeIndex,
    required this.textColor,
    required this.activeColor,
    required this.onSeek,
  });

  final List<LyricLine> lines;
  final int activeIndex;
  final Color textColor;
  final Color activeColor;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 86.0;
  static const double _listPadding = 24.0;
  final Map<int, double> _itemHeights = {};
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    if (widget.activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (widget.activeIndex != oldWidget.activeIndex && widget.activeIndex >= 0) {
      _scrollToActive();
    }
  }

  void _syncKeys() {
    if (_itemKeys.length == widget.lines.length) return;
    _itemKeys
      ..clear()
      ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
  }

  void _recordItemHeight(int index) {
    if (index < 0 || index >= _itemKeys.length) return;
    final ctx = _itemKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final height = box.size.height;
    final prev = _itemHeights[index];
    if (prev == height) return;
    _itemHeights[index] = height;
    if (index == widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  double _offsetForIndex(int index) {
    var offset = _listPadding;
    for (var i = 0; i < index; i++) {
      offset += _itemHeights[i] ?? _itemHeight;
    }
    return offset;
  }

  void _scrollToActive() {
    if (!_scrollController.hasClients || widget.activeIndex < 0) return;
    final viewportHeight = _scrollController.position.viewportDimension;
    final activeHeight = _itemHeights[widget.activeIndex] ?? _itemHeight;
    final itemTop = _offsetForIndex(widget.activeIndex);
    final target = itemTop - (viewportHeight - activeHeight) / 2;

    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: _listPadding),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final isActive = index == widget.activeIndex;
        final inheritedScale = MediaQuery.textScalerOf(context).scale(1.0);
        final cappedScale = inheritedScale > 1.35 ? 1.35 : inheritedScale;
        WidgetsBinding.instance.addPostFrameCallback((_) => _recordItemHeight(index));
        return Center(
          child: ConstrainedBox(
            key: _itemKeys[index],
            constraints: const BoxConstraints(minHeight: _itemHeight),
            child: InkWell(
              onTap: () => widget.onSeek(widget.lines[index].time),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isActive ? 34 : 24,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? widget.activeColor : widget.textColor.withValues(alpha: 0.6),
                  ),
                  child: Text(
                    widget.lines[index].text,
                    textScaler: TextScaler.linear(cappedScale),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CavaVisualizerPainter extends StatefulWidget {
  const _CavaVisualizerPainter({
    required this.stream,
    required this.color,
  });

  final Stream<List<double>> stream;
  final Color color;

  @override
  State<_CavaVisualizerPainter> createState() => _CavaVisualizerPainterState();
}

class _CavaVisualizerPainterState extends State<_CavaVisualizerPainter> {
  List<double> _data = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen((data) {
      if (mounted) {
        setState(() => _data = data);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CavaPainter(_data, widget.color),
    );
  }
}

class _CavaPainter extends CustomPainter {
  _CavaPainter(this.data, this.color);

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxValue = data.reduce(max);
    if (maxValue <= 0) return;

    final center = size.center(Offset.zero);
    final shortest = min(size.width, size.height);

    // Inner hole: tuned so ring stays outside the album art (which is smaller than this size box)
    final innerRadius = shortest * 0.42;
    final maxBarHeight = shortest * 0.20;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final angleStep = 2 * pi / data.length;
    final baseStroke = (2 * pi * innerRadius / data.length).clamp(3.0, 14.0);

    for (int i = 0; i < data.length; i++) {
      final value = (data[i] / maxValue).clamp(0.0, 1.0);
      if (value < 0.015) continue;

      final barH = value * maxBarHeight;
      final angle = i * angleStep - (pi / 2);

      final r1 = innerRadius;
      final r2 = innerRadius + barH;

      final p1 = Offset(center.dx + r1 * cos(angle), center.dy + r1 * sin(angle));
      final p2 = Offset(center.dx + r2 * cos(angle), center.dy + r2 * sin(angle));

      paint.strokeWidth = baseStroke;
      // Slight alpha modulation makes motion pop a bit more
      paint.color = color.withValues(alpha: (0.45 + 0.55 * value).clamp(0.0, 1.0));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CavaPainter oldDelegate) {
    return data != oldDelegate.data;
  }
}

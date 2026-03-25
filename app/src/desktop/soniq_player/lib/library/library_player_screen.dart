import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import '../cava_visualizer.dart';
import '../screens/history_screen.dart';
import '../player_widgets.dart';
import '../playlists/playlists_controller.dart';
import '../screens/playlist_tracks_screen.dart';
import '../main.dart' show setLastPlayerKind, LastPlayerKind, isOnHomeMenu;
import '../i18n.dart';
import '../screens/settings.dart';
import '../remote_control_server.dart';
/// Player dla Biblioteki.
///
/// W odróżnieniu od `MusicPlayerScreen`, nie ma wyboru katalogu.
/// Zakłada, że playlista została już załadowana i steruje globalnym AudioController.
class LibraryPlayerScreen extends StatefulWidget {
  const LibraryPlayerScreen({super.key, this.title, this.settingsController});

  final String? title;
  final SettingsController? settingsController;

  @override
  State<LibraryPlayerScreen> createState() => _LibraryPlayerScreenState();
}

class _LibraryPlayerScreenState extends State<LibraryPlayerScreen> {
  final AudioController _audio = AudioController();
  final CavaController _cava = CavaController();
  bool _showLyrics = false;
  bool _showVisualizerInsteadOfCover = false;

  static const double _swipeMinVelocity = 650.0;

  Future<void> _togglePlayPause(AudioState audioState) async {
    if (audioState.isPlaying) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  @override
  void dispose() {
    _audio.state.removeListener(_onAudioStateChanged);
    _cava.stop();
    RemoteControlServer.instance.removeListener(_syncRemoteOverlayState);
    super.dispose();
  }

  void _onAudioStateChanged() {
    if (_audio.state.value.isPlaying) {
      _cava.start();
    } else {
      _cava.stop();
    }
  }

  void _openTrackList() {
    final playlist = _audio.playlist;
    if (playlist.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistTracksScreen(
          title: 'trackList',
          audio: _audio,
          playlistsController: PlaylistsController.instance,
        ),
      ),
    );
  }

  void _syncRemoteOverlayState() {
    final remote = RemoteControlServer.instance;
    final nextVisualizer = remote.showVisualizer;
    final nextLyrics = remote.showLyrics;
    var needsImmediateSetState = false;

    if (_showVisualizerInsteadOfCover != nextVisualizer) {
      _showVisualizerInsteadOfCover = nextVisualizer;
      needsImmediateSetState = true;
    }

    final playlist = _audio.playlist;
    if (!nextLyrics || playlist.isEmpty) {
      if (_showLyrics != false || _showVisualizerInsteadOfCover != nextVisualizer) {
        if (mounted) {
          setState(() {
            _showLyrics = false;
            _showVisualizerInsteadOfCover = nextVisualizer;
          });
        }
      } else if (mounted && needsImmediateSetState) {
        setState(() {});
      }
      return;
    }

    final currentIndex = _audio.state.value.currentIndex.clamp(0, playlist.length - 1);
    final currentPath = playlist[currentIndex];
    _audio.getMetadata(currentPath, forceRefresh: true).then((metaNow) {
      if (!mounted) return;
      final hasLyrics = metaNow.lyrics != null && metaNow.lyrics!.trim().isNotEmpty;
      final resolvedLyrics = nextLyrics && hasLyrics;
      if (_showLyrics != resolvedLyrics || _showVisualizerInsteadOfCover != nextVisualizer) {
        setState(() {
          _showLyrics = resolvedLyrics;
          _showVisualizerInsteadOfCover = nextVisualizer;
        });
      } else if (needsImmediateSetState) {
        setState(() {});
      }
    });
  }

  @override
  void initState() {
    super.initState();
    isOnHomeMenu.value = false;
    setLastPlayerKind(LastPlayerKind.library);
    _audio.state.addListener(_onAudioStateChanged);
    if (_audio.state.value.isPlaying) {
      _cava.start();
    }
    RemoteControlServer.instance.addListener(_syncRemoteOverlayState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRemoteOverlayState());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? strings.get('appTitle')),
        backgroundColor: cs.inversePrimary,
        actions: [
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

                return PopupMenuButton<String>(
                  icon: const Icon(Icons.speaker),
                  tooltip: strings.get('audioOutput'),
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
                              color: isSelected ? cs.primary : null,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                device.description,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? cs.primary : null,
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: ValueListenableBuilder<AudioState>(
          valueListenable: _audio.state,
          builder: (context, audioState, _) {
            final position = audioState.position;

            final playlist = _audio.playlist;
            final hasPlaylist = playlist.isNotEmpty;
            final currentIndex = hasPlaylist
                ? audioState.currentIndex.clamp(0, playlist.length - 1)
                : 0;
            final currentPath = hasPlaylist ? playlist[currentIndex] : null;


            final meta = currentPath != null ? _audio.metadataForPath(currentPath) : null;

            final currentTitle = meta?.title?.trim().isNotEmpty == true
                ? meta!.title!.trim()
                : (currentPath != null ? p.basename(currentPath) : '');

            final topSection = Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _togglePlayPause(audioState),
                  onLongPress: _openTrackList,
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() < _swipeMinVelocity) return;
                    if (v > 0) {
                      _audio.back();
                    } else {
                      _audio.next();
                    }
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.maxWidth < constraints.maxHeight
                                  ? constraints.maxWidth
                                  : constraints.maxHeight;
                              final effectiveSize = size > 600 ? 600.0 : size;
                              return Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (_showVisualizerInsteadOfCover)
                                      SizedBox(
                                        width: effectiveSize + 90,
                                        height: effectiveSize + 90,
                                        child: IgnorePointer(
                                          child: Opacity(
                                            opacity: 1.0,
                                            child: CavaVisualizerPainter(
                                              stream: _cava.dataStream,
                                              color: cs.brightness == Brightness.dark
                                                  ? const Color(0xFFFFFF00)
                                                  : cs.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_showVisualizerInsteadOfCover) ...[
                                      SizedBox(
                                        width: effectiveSize,
                                        height: effectiveSize,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: ColoredBox(
                                            color: Colors.transparent,
                                            child: Center(
                                              child: CavaVisualizerPainter(
                                                stream: _cava.dataStream,
                                                color: cs.brightness == Brightness.dark
                                                    ? const Color(0xFFFFFF00)
                                                    : cs.primary,
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
                                          color: cs.surfaceContainerHighest,
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
                                        child: Builder(builder: (_) {
                                          if (currentPath == null) {
                                            return Icon(
                                              Icons.music_note,
                                              size: effectiveSize * 0.5,
                                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                            );
                                          }
                                          final m = _audio.metadataForPath(currentPath);
                                          if (m?.coverBytes != null && m!.coverBytes!.isNotEmpty) {
                                            return Image.memory(m.coverBytes!, fit: BoxFit.cover);
                                          }
                                          if (m?.coverPath != null) {
                                            return Image.file(
                                              File(m!.coverPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Icon(
                                                Icons.music_note,
                                                size: effectiveSize * 0.5,
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                              ),
                                            );
                                          }
                                          return Icon(
                                            Icons.music_note,
                                            size: effectiveSize * 0.5,
                                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                          );
                                        }),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0, top: 16.0, bottom: 16.0),
                          child: _showLyrics
                              ? LyricsView(
                                  lyrics: meta?.lyrics ?? '',
                                  position: position,
                                  onClose: () => setState(() => _showLyrics = false),
                                  textColor: cs.onSurface,
                                  activeColor: cs.primary,
                                  onSeek: (time) => _audio.seek(time),
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
                                        meta?.album?.trim().isNotEmpty == true ? meta!.album!.trim() : '',
                                        style: TextStyle(fontSize: 36, color: cs.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        meta?.artist?.trim().isNotEmpty == true ? meta!.artist!.trim() : '',
                                        style: TextStyle(fontSize: 32, color: cs.onSurfaceVariant),
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
              ),
            );

            final controlsPanel = PlayerControlsPanel(
              audio: _audio,
              audioState: audioState,
              settingsController: widget.settingsController,
              strings: strings,
              canOpenTrackList: hasPlaylist,
              currentTrackPath: currentPath,
              onGoHome: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                isOnHomeMenu.value = true;
              },
              onOpenTrackList: _openTrackList,
              onOpenHistory: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen()));
              },
              onToggleVisualizer: () {
                setState(() => _showVisualizerInsteadOfCover = !_showVisualizerInsteadOfCover);
              },
              onToggleLyrics: () async {
                if (_showLyrics) {
                  setState(() => _showLyrics = false);
                  return;
                }
                if (!hasPlaylist || currentPath == null) return;
                final metaNow = await _audio.getMetadata(currentPath, forceRefresh: true);
                if (!mounted) return;
                final hasLyrics = metaNow.lyrics != null && metaNow.lyrics!.trim().isNotEmpty;
                if (hasLyrics) {
                  setState(() => _showLyrics = true);
                } else {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  messenger?.hideCurrentSnackBar();
                  messenger?.showSnackBar(
                    SnackBar(content: Text(strings.get('noLyrics'))),
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
    );
  }
}

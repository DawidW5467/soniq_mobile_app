import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import '../i18n.dart';
import '../main.dart' show TouchFriendlyScrollBehavior;
import '../playlists/playlists_controller.dart';
import '../playlists/playlists_screen.dart';
import 'settings.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({
    super.key,
    required this.settingsController,
    required this.directory,
    required this.files,
    this.playlistsController,
  });

  final SettingsController settingsController;
  final String directory;
  final List<File> files;
  final PlaylistsController? playlistsController;

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final AudioController _audioController = AudioController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoadingTrack = false;

  late final PlaylistsController _playlists = widget.playlistsController ?? PlaylistsController.instance;

  @override
  void initState() {
    super.initState();
    // Best-effort init (bez blokowania UI)
    _playlists.ensureLoaded();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<File> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.files;

    return widget.files.where((f) {
      final base = p.basename(f.path).toLowerCase();
      if (base.contains(q)) return true;
      final meta = _audioController.metadataForPath(f.path);
      if (meta == null) return false;

      bool has(String? s) => s != null && s.toLowerCase().contains(q);
      return has(meta.title) || has(meta.artist) || has(meta.album);
    }).toList();
  }

  Future<void> _addToPlaylistDialog(String trackPath) async {
    await _playlists.ensureLoaded();
    if (!mounted) return;

    final t = AppStrings.of(context);
    final nameCtrl = TextEditingController();
    try {
      final selected = await showDialog<String?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(t.get('addToPlaylist')),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pl in _playlists.playlists)
                    ListTile(
                      title: Text(pl.name),
                      subtitle: Text('${pl.items.length} ${t.get('tracksCount')}'),
                      onTap: () => Navigator.pop(context, pl.id),
                    ),
                  const Divider(),
                  Text(t.get('newPlaylist')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: t.get('playlistName'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(t.get('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, '__create__:$name');
                },
                child: Text(t.get('createAndAdd')),
              ),
            ],
          );
        },
      );

      if (selected == null) return;

      String playlistId;
      if (selected.startsWith('__create__:')) {
        final name = selected.substring('__create__:'.length);
        playlistId = await _playlists.createPlaylist(name);
      } else {
        playlistId = selected;
      }

      await _playlists.addTrack(playlistId: playlistId, path: trackPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('addedToPlaylist'))),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final files = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('music')),
        backgroundColor: colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: t.get('playlists'),
            icon: const Icon(Icons.playlist_play),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistsScreen(
                    playlistsController: _playlists,
                    settingsController: widget.settingsController,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Scrollbar(
            thumbVisibility: true,
            thickness: 12,
            radius: const Radius.circular(8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: t.get('searchTracksHint'),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _searchCtrl.clear();
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.directory,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Text('${files.length}/${widget.files.length}'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: files.isEmpty
                      ? Center(child: Text(t.get('noResults')))
                      : ValueListenableBuilder<AudioState>(
                          valueListenable: _audioController.state,
                          builder: (context, audioState, _) {
                            return ScrollConfiguration(
                              behavior: const TouchFriendlyScrollBehavior(),
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: files.length,
                                separatorBuilder: (context, index) => const Divider(height: 2),
                                itemBuilder: (context, index) {
                                  final file = files[index];
                                  return FutureBuilder<AudioMetadata>(
                                    initialData: _audioController.metadataForPath(file.path),
                                    future: _audioController.getMetadata(file.path),
                                    builder: (context, snapshot) {
                                      final meta = snapshot.data;

                                      // Check if this file is currently playing
                                      final currentPath = (_audioController.playlist.isNotEmpty &&
                                              _audioController.currentIndex >= 0 &&
                                              _audioController.currentIndex < _audioController.playlist.length)
                                          ? _audioController.playlist[_audioController.currentIndex]
                                          : null;

                                      final isPlaying = file.path == currentPath;
                                      final isSelected = isPlaying;

                                      final title = meta?.title?.trim();
                                      final artist = meta?.artist?.trim();
                                      final displayName = (title != null && title.isNotEmpty)
                                          ? title
                                          : p.basename(file.path);

                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        minVerticalPadding: 14,
                                        leading: Icon(
                                          isPlaying ? Icons.play_circle_filled : Icons.music_note,
                                          color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                                          size: 44,
                                        ),
                                        title: Text(
                                          displayName,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? Theme.of(context).colorScheme.primary : null,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: (artist != null && artist.isNotEmpty)
                                            ? Text(
                                                artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                                                      : null,
                                                ),
                                              )
                                            : null,
                                        trailing: PopupMenuButton<String>(
                                          padding: const EdgeInsets.all(14),
                                          tooltip: t.get('options'),
                                          onSelected: (value) async {
                                            if (value == 'add_to_playlist') {
                                              await _addToPlaylistDialog(file.path);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'add_to_playlist',
                                              child: Text(t.get('addToPlaylist')),
                                            ),
                                          ],
                                        ),
                                        onLongPress: () => _addToPlaylistDialog(file.path),
                                        onTap: () async {
                                          if (_isLoadingTrack) return;
                                          setState(() => _isLoadingTrack = true);
                                          try {
                                            final allPaths = widget.files.map((f) => f.path).toList();
                                            final fullIndex = allPaths.indexOf(file.path);
                                            final startIndex = fullIndex >= 0 ? fullIndex : index;
                                            _audioController.resetPlaylistMode();
                                            await _audioController.loadPlaylist(allPaths, startIndex: startIndex);
                                            await _audioController.play();
                                            if (!context.mounted) return;
                                            Navigator.pop(context);
                                          } finally {
                                            if (mounted) {
                                              setState(() => _isLoadingTrack = false);
                                            }
                                          }
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (_isLoadingTrack)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface.withValues(alpha: 0.85),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        t.get('loadingTrack'),
                        style: TextStyle(color: colorScheme.onSurface),
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

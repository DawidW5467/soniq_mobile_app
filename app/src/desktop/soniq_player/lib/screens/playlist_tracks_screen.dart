import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import '../i18n.dart';
import '../playlists/playlists_controller.dart';
import '../main.dart' show TouchFriendlyScrollBehavior;

class PlaylistTracksScreen extends StatefulWidget {
  const PlaylistTracksScreen({
    super.key,
    required this.title,
    required this.audio,
    required this.playlistsController,
  });

  final String title;
  final AudioController audio;
  final PlaylistsController playlistsController;

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoadingTrack = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _filteredPaths {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.audio.playlist;

    return widget.audio.playlist.where((path) {
      final base = p.basename(path).toLowerCase();
      if (base.contains(q)) return true;
      final meta = widget.audio.metadataForPath(path);
      if (meta == null) return false;

      bool has(String? s) => s != null && s.toLowerCase().contains(q);
      return has(meta.title) || has(meta.artist) || has(meta.album);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final playlist = widget.audio.playlist;
    final files = _filteredPaths;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get(widget.title)),
        backgroundColor: colorScheme.inversePrimary,
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
                const Divider(height: 1),
                Expanded(
                  child: files.isEmpty
                      ? Center(child: Text(t.get('noResults')))
                      : ValueListenableBuilder<AudioState>(
                          valueListenable: widget.audio.state,
                          builder: (context, audioState, _) {
                            return ScrollConfiguration(
                              behavior: const TouchFriendlyScrollBehavior(),
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: files.length,
                                separatorBuilder: (context, index) => const Divider(height: 2),
                                itemBuilder: (context, index) {
                                  final path = files[index];
                                  return FutureBuilder<AudioMetadata>(
                                    initialData: widget.audio.metadataForPath(path),
                                    future: widget.audio.getMetadata(path),
                                    builder: (context, snapshot) {
                                      final meta = snapshot.data;
                                      final currentPath = (playlist.isNotEmpty &&
                                              widget.audio.currentIndex >= 0 &&
                                              widget.audio.currentIndex < playlist.length)
                                          ? playlist[widget.audio.currentIndex]
                                          : null;

                                      final isPlaying = path == currentPath;
                                      final title = meta?.title?.trim();
                                      final artist = meta?.artist?.trim();
                                      final displayName = (title != null && title.isNotEmpty)
                                          ? title
                                          : p.basename(path);

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
                                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                            color: isPlaying ? Theme.of(context).colorScheme.primary : null,
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
                                                  color: isPlaying
                                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                                                      : null,
                                                ),
                                              )
                                            : null,
                                        onTap: () async {
                                          if (_isLoadingTrack) return;
                                          setState(() => _isLoadingTrack = true);
                                          try {
                                            final fullIndex = playlist.indexOf(path);
                                            final startIndex = fullIndex >= 0 ? fullIndex : index;
                                            await widget.audio.playAtIndex(startIndex);
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


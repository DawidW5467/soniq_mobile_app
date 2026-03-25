import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../audio_controller.dart';
import '../main.dart';
import '../screens/settings.dart';
import '../i18n.dart';
import 'playlist_models.dart';
import 'playlists_controller.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistsController,
    required this.settingsController,
  });

  final String playlistId;
  final PlaylistsController playlistsController;
  final SettingsController settingsController;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final AudioController _audio = AudioController();

  PlaylistSortKey _sortKey = PlaylistSortKey.addedAt;
  SortDirection _sortDir = SortDirection.asc;
  bool _sortedViewOnly = true;

  @override
  void initState() {
    super.initState();
    widget.playlistsController.ensureLoaded();
  }

  Future<List<PlaylistItem>> _itemsForView() async {
    final pl = widget.playlistsController.getById(widget.playlistId);
    if (pl == null) return const [];

    if (!_sortedViewOnly) return pl.items;
    return widget.playlistsController.getSortedView(
      playlistId: widget.playlistId,
      key: _sortKey,
      direction: _sortDir,
    );
  }

  Future<void> _playFromView({required List<PlaylistItem> items, required int index}) async {
    if (items.isEmpty) return;

    // Filtruj brakujące pliki, żeby audioplayers nie startował z pustym/błędnym źródłem.
    final existing = <String>[];
    for (final it in items) {
      try {
        if (await File(it.path).exists()) {
          existing.add(it.path);
        }
      } catch (_) {}
    }
    if (existing.isEmpty) return;

    final start = index.clamp(0, existing.length - 1);
    await _audio.loadPlaylist(existing, startIndex: start, fromUserPlaylist: true);
    await _audio.play();

    if (!mounted) return;
    // Przenieś do widoku sterowania (playera).
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerScreen(settingsController: widget.settingsController),
      ),
    );
  }

  Future<void> _playVisibleFromStart() async {
    final items = await _itemsForView();
    await _playFromView(items: items, index: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('playlist')),
        backgroundColor: colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: t.get('play'),
            onPressed: _playVisibleFromStart,
            icon: const Icon(Icons.play_arrow),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'dedupe') {
                await widget.playlistsController.dedupeByPath(playlistId: widget.playlistId);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'dedupe', child: Text(t.get('dedupeByPath'))),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.playlistsController,
        builder: (context, _) {
          final pl = widget.playlistsController.getById(widget.playlistId);
          if (pl == null) {
            return Center(child: Text(t.get('playlistNotFound')));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pl.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<PlaylistSortKey>(
                      value: _sortKey,
                      onChanged: (v) => setState(() => _sortKey = v ?? _sortKey),
                      items: [
                        DropdownMenuItem(value: PlaylistSortKey.addedAt, child: Text(t.get('sort_addedAt'))),
                        DropdownMenuItem(value: PlaylistSortKey.fileName, child: Text(t.get('sort_fileName'))),
                        DropdownMenuItem(value: PlaylistSortKey.title, child: Text(t.get('sort_title'))),
                        DropdownMenuItem(value: PlaylistSortKey.artist, child: Text(t.get('sort_artist'))),
                        DropdownMenuItem(value: PlaylistSortKey.album, child: Text(t.get('sort_album'))),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t.get('sortDirection'),
                      onPressed: () => setState(() {
                        _sortDir = _sortDir == SortDirection.asc ? SortDirection.desc : SortDirection.asc;
                      }),
                      icon: Icon(_sortDir == SortDirection.asc ? Icons.arrow_upward : Icons.arrow_downward),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(_sortedViewOnly ? t.get('sortedView') : t.get('orderView')),
                      selected: _sortedViewOnly,
                      onSelected: (v) => setState(() => _sortedViewOnly = v),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () async {
                        await widget.playlistsController.applySort(
                          playlistId: widget.playlistId,
                          key: _sortKey,
                          direction: _sortDir,
                        );
                      },
                      child: Text(t.get('apply')),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<PlaylistItem>>(
                  future: _itemsForView(),
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    if (items.isEmpty) {
                      return Center(child: Text(t.get('emptyPlaylist')));
                    }

                    if (!_sortedViewOnly) {
                      return ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        onReorder: (oldIndex, newIndex) async {
                          await widget.playlistsController.moveItem(
                            playlistId: widget.playlistId,
                            oldIndex: oldIndex,
                            newIndex: newIndex,
                          );
                        },
                        itemBuilder: (context, index) {
                          final it = items[index];
                          return _PlaylistItemTile(
                            key: ValueKey(it.id),
                            item: it,
                            audio: _audio,
                            onRemove: () async {
                              await widget.playlistsController.removeItem(
                                playlistId: widget.playlistId,
                                itemId: it.id,
                              );
                            },
                            onPlay: () async {
                              // items[] to lista w aktualnym widoku (manual)
                              await _playFromView(items: items, index: index);
                            },
                          );
                        },
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final it = items[index];
                        return _PlaylistItemTile(
                          key: ValueKey(it.id),
                          item: it,
                          audio: _audio,
                          onRemove: () async {
                            await widget.playlistsController.removeItem(
                              playlistId: widget.playlistId,
                              itemId: it.id,
                            );
                          },
                          onPlay: () async {
                            // items[] to lista w aktualnym widoku (sorted)
                            await _playFromView(items: items, index: index);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlaylistItemTile extends StatelessWidget {
  const _PlaylistItemTile({
    super.key,
    required this.item,
    required this.audio,
    required this.onRemove,
    this.onPlay,
  });

  final PlaylistItem item;
  final AudioController audio;
  final VoidCallback onRemove;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final name = p.basename(item.path);

    return FutureBuilder<AudioMetadata>(
      future: audio.getMetadata(item.path),
      initialData: audio.metadataForPath(item.path),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        final title = (meta?.title ?? '').trim();
        final artist = (meta?.artist ?? '').trim();
        final display = title.isNotEmpty ? title : name;

        return ListTile(
          title: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: artist.isNotEmpty
              ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          leading: const Icon(Icons.music_note),
          trailing: IconButton(
            tooltip: t.get('removeFromPlaylist'),
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
          onTap: onPlay,
        );
      },
    );
  }
}

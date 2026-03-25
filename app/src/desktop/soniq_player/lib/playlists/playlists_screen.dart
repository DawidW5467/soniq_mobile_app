import 'package:flutter/material.dart';

import '../i18n.dart';
import '../screens/settings.dart';
import 'playlist_detail_screen.dart';
import 'playlists_controller.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.playlistsController,
    required this.settingsController,
  });

  final PlaylistsController playlistsController;
  final SettingsController settingsController;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    widget.playlistsController.ensureLoaded();
  }

  Future<void> _createPlaylist() async {
    final t = AppStrings.of(context);
    final ctrl = TextEditingController();
    try {
      final name = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.get('newPlaylist')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: t.get('playlistName')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.get('cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(t.get('create')),
            ),
          ],
        ),
      );

      if (name == null || name.trim().isEmpty) return;
      await widget.playlistsController.createPlaylist(name);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _renamePlaylist(String playlistId, String currentName) async {
    final t = AppStrings.of(context);
    final ctrl = TextEditingController(text: currentName);
    try {
      final name = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.get('renamePlaylist')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: t.get('playlistName')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.get('cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(t.get('save')),
            ),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      await widget.playlistsController.renamePlaylist(playlistId: playlistId, name: name);
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('playlists')),
        backgroundColor: colorScheme.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
      body: AnimatedBuilder(
        animation: widget.playlistsController,
        builder: (context, _) {
          final playlists = widget.playlistsController.playlists;
          if (playlists.isEmpty) {
            return Center(child: Text(t.get('noPlaylists')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final pl = playlists[index];
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(pl.name),
                subtitle: Text('${pl.items.length} ${t.get('itemsCount')}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(
                        playlistId: pl.id,
                        playlistsController: widget.playlistsController,
                        settingsController: widget.settingsController,
                      ),
                    ),
                  );
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'rename') {
                      await _renamePlaylist(pl.id, pl.name);
                    } else if (value == 'delete') {
                      await widget.playlistsController.deletePlaylist(pl.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text(t.get('renamePlaylist'))),
                    PopupMenuItem(value: 'delete', child: Text(t.get('delete'))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import '../i18n.dart';
import '../main.dart' show TouchFriendlyScrollBehavior;

class HistoryScreen extends StatelessWidget {
  HistoryScreen({super.key});

  final AudioController _audio = AudioController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('history')),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            tooltip: t.get('clearHistory'),
            onPressed: () {
              _audio.clearHistory();
              (context as Element).markNeedsBuild();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ValueListenableBuilder<AudioState>(
        valueListenable: _audio.state,
        builder: (context, audioState, _) {
          final items = _audio.history.toList().reversed.toList();
          if (items.isEmpty) {
            return Center(child: Text(t.get('noResults')));
          }

          return ScrollConfiguration(
            behavior: const TouchFriendlyScrollBehavior(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 2),
              itemBuilder: (context, index) {
                final path = items[index];
                final meta = _audio.metadataForPath(path);
                final title = meta?.title?.trim();
                final artist = meta?.artist?.trim();
                final displayName = (title != null && title.isNotEmpty) ? title : p.basename(path);

                final isCurrent = _audio.playlist.isNotEmpty &&
                    audioState.currentIndex >= 0 &&
                    audioState.currentIndex < _audio.playlist.length &&
                    _audio.playlist[audioState.currentIndex] == path;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  minVerticalPadding: 14,
                  leading: Icon(isCurrent ? Icons.play_circle_filled : Icons.history, size: 40),
                  title: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? cs.primary : null,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (artist != null && artist.isNotEmpty) artist,
                      p.dirname(path),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    final idx = _audio.playlist.indexOf(path);
                    if (idx >= 0) {
                      await _audio.playAtIndex(idx);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

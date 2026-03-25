import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_controller.dart';
import 'library_controller.dart';
import 'library_models.dart';
import '../main.dart' show TouchFriendlyScrollBehavior;
import '../i18n.dart';
import '../screens/settings.dart';
import 'library_player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.sources, this.settingsController});

  final Map<String, String> sources;
  final SettingsController? settingsController;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final LibraryController _lib = LibraryController.instance;
  final AudioController _audio = AudioController();
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lib.scheduleRebuild(widget.sources);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lib.rebuild(sources: widget.sources);
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('library_all')),
        backgroundColor: cs.inversePrimary,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _lib.isIndexing,
            builder: (context, indexing, _) {
              if (!indexing) {
                return IconButton(
                  tooltip: strings.get('refresh'),
                  onPressed: () => _lib.rebuild(sources: widget.sources),
                  icon: const Icon(Icons.refresh),
                );
              }
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.get('searchLibraryHint'),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _search.clear()),
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<LibraryIndex>(
              valueListenable: _lib.index,
              builder: (context, idx, _) {
                return DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          Tab(text: strings.get('albums')),
                          Tab(text: strings.get('artists')),
                          Tab(text: strings.get('tracks')),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _AlbumsTab(
                              albums: _filterAlbums(idx.albums, _search.text),
                              audio: _audio,
                              strings: strings,
                              settingsController: widget.settingsController,
                            ),
                            _ArtistsTab(
                              artists: _filterArtists(idx.artists, _search.text),
                              audio: _audio,
                              strings: strings,
                              settingsController: widget.settingsController,
                            ),
                            _TracksTab(
                              tracks: _filterTracks(idx.tracks, _search.text),
                              audio: _audio,
                              strings: strings,
                              settingsController: widget.settingsController,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<LibraryTrack> _filterTracks(List<LibraryTrack> items, String qRaw) {
    final q = qRaw.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((t) {
      return t.titleOrFileName.toLowerCase().contains(q) ||
          t.artistOrUnknown.toLowerCase().contains(q) ||
          t.albumOrUnknown.toLowerCase().contains(q) ||
          t.path.toLowerCase().contains(q);
    }).toList();
  }

  List<LibraryAlbum> _filterAlbums(List<LibraryAlbum> items, String qRaw) {
    final q = qRaw.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((a) {
      return a.name.toLowerCase().contains(q) || a.artistKey.toLowerCase().contains(q);
    }).toList();
  }

  List<LibraryArtist> _filterArtists(List<LibraryArtist> items, String qRaw) {
    final q = qRaw.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((a) {
      return a.name.toLowerCase().contains(q);
    }).toList();
  }
}

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab({
    required this.albums,
    required this.audio,
    required this.strings,
    this.settingsController,
  });

  final List<LibraryAlbum> albums;
  final AudioController audio;
  final AppStrings strings;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return Center(child: Text(strings.get('noAlbums')));

    return ScrollConfiguration(
      behavior: const TouchFriendlyScrollBehavior(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const Divider(height: 2),
        itemBuilder: (context, index) {
          final a = albums[index];
          final cover = a.tracks.isNotEmpty ? a.tracks.first.meta.coverPath : null;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minVerticalPadding: 14,
            leading: _CoverThumb(path: cover),
            title: Text(
              '${a.artistKey} — ${a.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20),
            ),
            subtitle: Text(
              '${a.tracks.length} ${strings.get('tracksCount')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _AlbumDetailsScreen(
                    album: a,
                    audio: audio,
                    strings: strings,
                    settingsController: settingsController,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab({
    required this.artists,
    required this.audio,
    required this.strings,
    this.settingsController,
  });

  final List<LibraryArtist> artists;
  final AudioController audio;
  final AppStrings strings;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return Center(child: Text(strings.get('noArtists')));

    return ScrollConfiguration(
      behavior: const TouchFriendlyScrollBehavior(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: artists.length,
        separatorBuilder: (_, _) => const Divider(height: 2),
        itemBuilder: (context, index) {
          final a = artists[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minVerticalPadding: 14,
            leading: const Icon(Icons.person),
            title: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20),
            ),
            subtitle: Text(
              '${a.tracks.length} ${strings.get('tracksCount')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ArtistDetailsScreen(
                    artist: a,
                    audio: audio,
                    strings: strings,
                    settingsController: settingsController,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TracksTab extends StatelessWidget {
  const _TracksTab({
    required this.tracks,
    required this.audio,
    required this.strings,
    this.settingsController,
  });

  final List<LibraryTrack> tracks;
  final AudioController audio;
  final AppStrings strings;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return Center(child: Text(strings.get('noTracks')));

    return ScrollConfiguration(
      behavior: const TouchFriendlyScrollBehavior(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const Divider(height: 2),
        itemBuilder: (context, index) {
          final t = tracks[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minVerticalPadding: 14,
            leading: _CoverThumb(path: t.meta.coverPath),
            title: Text(
              t.titleOrFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20),
            ),
            subtitle: Text(
              '${t.artistOrUnknown} • ${t.albumOrUnknown}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              await audio.loadPlaylist([for (final x in tracks) x.path], startIndex: index);
              await audio.play();
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LibraryPlayerScreen(
                    title: strings.get('library_all'),
                    settingsController: settingsController,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AlbumDetailsScreen extends StatelessWidget {
  const _AlbumDetailsScreen({
    required this.album,
    required this.audio,
    required this.strings,
    this.settingsController,
  });

  final LibraryAlbum album;
  final AudioController audio;
  final AppStrings strings;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${album.artistKey} — ${album.name}'),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            tooltip: strings.get('playAlbum'),
            onPressed: () async {
              await audio.loadPlaylist([for (final t in album.tracks) t.path], startIndex: 0);
              await audio.play();
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LibraryPlayerScreen(
                    title: strings.get('playAlbum'),
                    settingsController: settingsController,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: const TouchFriendlyScrollBehavior(),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: album.tracks.length,
          separatorBuilder: (_, _) => const Divider(height: 2),
          itemBuilder: (context, index) {
            final t = album.tracks[index];
            final tn = t.meta.trackNumber;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minVerticalPadding: 14,
              leading: Text(
                tn != null ? tn.toString().padLeft(2, '0') : '--',
                style: const TextStyle(fontSize: 18),
              ),
              title: Text(
                t.titleOrFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20),
              ),
              subtitle: Text(
                '${t.artistOrUnknown} • ${t.albumOrUnknown}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                await audio.loadPlaylist([for (final x in album.tracks) x.path], startIndex: index);
                await audio.play();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LibraryPlayerScreen(
                      title: strings.get('playAlbum'),
                      settingsController: settingsController,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ArtistDetailsScreen extends StatelessWidget {
  const _ArtistDetailsScreen({
    required this.artist,
    required this.audio,
    required this.strings,
    this.settingsController,
  });

  final LibraryArtist artist;
  final AudioController audio;
  final AppStrings strings;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(artist.name),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            tooltip: strings.get('playAll'),
            onPressed: () async {
              await audio.loadPlaylist([for (final t in artist.tracks) t.path], startIndex: 0);
              await audio.play();
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LibraryPlayerScreen(
                    title: strings.get('playAll'),
                    settingsController: settingsController,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: const TouchFriendlyScrollBehavior(),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: artist.tracks.length,
          separatorBuilder: (_, _) => const Divider(height: 2),
          itemBuilder: (context, index) {
            final t = artist.tracks[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minVerticalPadding: 14,
              leading: _CoverThumb(path: t.meta.coverPath),
              title: Text(
                t.titleOrFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20),
              ),
              subtitle: Text(
                '${t.artistOrUnknown} • ${t.albumOrUnknown}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                await audio.loadPlaylist([for (final x in artist.tracks) x.path], startIndex: index);
                await audio.play();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LibraryPlayerScreen(
                      title: strings.get('playAll'),
                      settingsController: settingsController,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pth = path;
    if (pth == null || pth.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note, color: cs.onSurfaceVariant),
      );
    }

    final file = File(pth);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: cs.surfaceContainerHighest,
              child: Icon(Icons.music_note, color: cs.onSurfaceVariant),
            );
          },
        ),
      ),
    );
  }
}

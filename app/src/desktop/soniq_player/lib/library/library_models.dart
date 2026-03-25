import '../audio_controller.dart';

class LibraryTrack {
  LibraryTrack({
    required this.path,
    required this.sourceName,
    required this.sourcePath,
    required this.meta,
  });

  final String path;
  final String sourceName;
  final String sourcePath;
  final AudioMetadata meta;

  String get titleOrFileName {
    final t = meta.title?.trim();
    return (t != null && t.isNotEmpty) ? t : path.split('/').last;
  }

  String get artistOrUnknown {
    final a = meta.artist?.trim();
    return (a != null && a.isNotEmpty) ? a : 'Nieznany artysta';
  }

  String get albumOrUnknown {
    final a = meta.album?.trim();
    return (a != null && a.isNotEmpty) ? a : 'Nieznany album';
  }
}

class LibraryAlbum {
  LibraryAlbum({required this.name, required this.artistKey, required this.tracks});

  final String name;
  final String artistKey;
  final List<LibraryTrack> tracks;
}

class LibraryArtist {
  LibraryArtist({required this.name, required this.tracks});

  final String name;
  final List<LibraryTrack> tracks;
}

class LibraryIndex {
  LibraryIndex({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.updatedAt,
  });

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;
  final DateTime updatedAt;

  factory LibraryIndex.empty() => LibraryIndex(
        tracks: const [],
        albums: const [],
        artists: const [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
}

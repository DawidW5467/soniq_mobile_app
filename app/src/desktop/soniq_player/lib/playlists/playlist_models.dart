import 'dart:convert';

/// Pojedynczy element playlisty.
///
/// Duplikaty są wspierane: ten sam [path] może wystąpić wiele razy, bo
/// unikalność zapewnia [id] elementu.
class PlaylistItem {
  PlaylistItem({
    required this.id,
    required this.path,
    required this.addedAtEpochMs,
  });

  final String id;
  final String path;
  final int addedAtEpochMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'addedAt': addedAtEpochMs,
      };

  static PlaylistItem fromJson(Map<String, Object?> json) {
    return PlaylistItem(
      id: (json['id'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      addedAtEpochMs: (json['addedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final String id;
  final String name;
  final List<PlaylistItem> items;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  Playlist copyWith({
    String? name,
    List<PlaylistItem>? items,
    int? updatedAtEpochMs,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAtEpochMs,
        'updatedAt': updatedAtEpochMs,
        'items': items.map((e) => e.toJson()).toList(),
      };

  static Playlist fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final items = <PlaylistItem>[];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map) {
          final m = it.map((k, v) => MapEntry(k.toString(), v)) as Map<String, Object?>;
          items.add(PlaylistItem.fromJson(m));
        }
      }
    }

    return Playlist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Playlista',
      createdAtEpochMs: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAtEpochMs: (json['updatedAt'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }
}

/// Root pliku JSON (wersjonowanie schematu + lista playlist).
class PlaylistsFile {
  PlaylistsFile({required this.schemaVersion, required this.playlists});

  final int schemaVersion;
  final List<Playlist> playlists;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'playlists': playlists.map((e) => e.toJson()).toList(),
      };

  static PlaylistsFile empty() => PlaylistsFile(schemaVersion: 1, playlists: const []);

  static PlaylistsFile fromJson(Map<String, Object?> json) {
    final ver = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    final raw = json['playlists'];
    final pls = <Playlist>[];

    if (raw is List) {
      for (final it in raw) {
        if (it is Map) {
          final m = it.map((k, v) => MapEntry(k.toString(), v)) as Map<String, Object?>;
          pls.add(Playlist.fromJson(m));
        }
      }
    }

    return PlaylistsFile(schemaVersion: ver, playlists: pls);
  }

  static PlaylistsFile decode(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map) {
      final m = decoded.map((k, v) => MapEntry(k.toString(), v)) as Map<String, Object?>;
      return fromJson(m);
    }
    return empty();
  }

  String encodePretty() => const JsonEncoder.withIndent('  ').convert(toJson());
}

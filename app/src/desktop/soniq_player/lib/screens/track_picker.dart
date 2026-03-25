import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../main.dart' show TouchFriendlyScrollBehavior;
import '../i18n.dart';

/// Minimalny selektor utworów dla playlisty.
///
/// - wyświetla listę plików audio z wielu źródeł naraz
/// - pozwala zaznaczać wiele pozycji
/// - zwraca List<String> ścieżek
class TrackPickerDialog extends StatefulWidget {
  const TrackPickerDialog({
    super.key,
    required this.sources,
    this.allowedExtensions = const ['.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'],
    this.initiallySelectedPaths = const {},
    this.title,
  });

  final String? title;

  /// Mapa: nazwa źródła -> ścieżka katalogu.
  ///
  /// Uwaga: zakładamy, że to katalog. Jeśli nie istnieje albo brak uprawnień, źródło jest pomijane.
  final Map<String, String> sources;

  final List<String> allowedExtensions;

  /// Wstępnie zaznaczone ścieżki (np. już dodane w playliście).
  final Set<String> initiallySelectedPaths;

  static Future<List<String>?> show(
    BuildContext context, {
    required Map<String, String> sources,
    Set<String> initiallySelectedPaths = const {},
    String? title,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: TrackPickerDialog(
            sources: sources,
            initiallySelectedPaths: initiallySelectedPaths,
            title: title,
          ),
        ),
      ),
    );
  }

  @override
  State<TrackPickerDialog> createState() => _TrackPickerDialogState();
}

class _TrackPickerDialogState extends State<TrackPickerDialog> {
  final TextEditingController _filterCtrl = TextEditingController();

  bool _loading = true;
  String? _error;

  /// Każdy element to plik audio.
  late List<_TrackRow> _all;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelectedPaths};
    _load();
    _filterCtrl.addListener(() {
      setState(() {
        // przebuduj listę
      });
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tracks = <_TrackRow>[];
      for (final entry in widget.sources.entries) {
        final sourceName = entry.key;
        final sourcePath = entry.value;
        if (sourcePath.trim().isEmpty) continue;

        final dir = Directory(sourcePath);
        if (!await dir.exists()) continue;

        // Skanujemy 1 poziom (tak jak w MusicPlayerScreen) – szybko i bez niespodzianek.
        // Jeśli będziesz chciał rekurencyjnie, dodamy opcję + limit.
        final entities = await dir.list(followLinks: false).toList();
        for (final e in entities) {
          if (e is! File) continue;
          final ext = p.extension(e.path).toLowerCase();
          if (!widget.allowedExtensions.contains(ext)) continue;
          tracks.add(
            _TrackRow(
              sourceName: sourceName,
              path: e.path,
              missing: !await e.exists(),
            ),
          );
        }
      }

      tracks.sort((a, b) {
        final c = a.sourceName.compareTo(b.sourceName);
        if (c != 0) return c;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      setState(() {
        _all = tracks;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _all = const [];
      });
    }
  }

  List<_TrackRow> get _filtered {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((t) {
      final name = p.basename(t.path).toLowerCase();
      return name.contains(q) || t.path.toLowerCase().contains(q) || t.sourceName.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleAllVisible(bool value) {
    final visible = _filtered;
    setState(() {
      for (final t in visible) {
        if (value) {
          _selected.add(t.path);
        } else {
          _selected.remove(t.path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = AppStrings.of(context);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.get('scanError')),
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(t.get('retry')),
                      ),
                    )
                  ],
                ),
              )
            : _all.isEmpty
                ? Center(child: Text(t.get('noTracksInSources')))
                : _TrackList(
                    tracks: _filtered,
                    selected: _selected,
                    onToggle: (path, value) {
                      setState(() {
                        if (value) {
                          _selected.add(path);
                        } else {
                          _selected.remove(path);
                        }
                      });
                    },
                  );

    final visible = !_loading && _error == null ? _filtered : const <_TrackRow>[];
    final allVisibleSelected = visible.isNotEmpty && visible.every((t) => _selected.contains(t.path));
    final anyVisibleSelected = visible.any((t) => _selected.contains(t.path));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title ?? t.get('pickTracks'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: t.get('refreshTooltip'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _filterCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t.get('searchByNamePathSource'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Checkbox(
                value: allVisibleSelected,
                tristate: true,
                onChanged: (v) {
                  final next = v == true ? false : true;
                  _toggleAllVisible(next);
                },
              ),
              const SizedBox(width: 6),
              Text(
                anyVisibleSelected
                    ? '${t.get('selectedCount')}: ${_selected.length}'
                    : t.get('selectAllVisible'),
              ),
              const Spacer(),
              Text('${visible.length}/${_all.length}'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.get('cancel')),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
                icon: const Icon(Icons.check),
                label: Text('${t.get('addN')} (${_selected.length})'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.selected,
    required this.onToggle,
  });

  final List<_TrackRow> tracks;
  final Set<String> selected;
  final void Function(String path, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const TouchFriendlyScrollBehavior(),
      child: ListView.separated(
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final t = tracks[index];
          final isSelected = selected.contains(t.path);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minVerticalPadding: 14,
            leading: t.missing
                ? const Icon(Icons.error_outline, color: Colors.red, size: 28)
                : const Icon(Icons.music_note, size: 28),
            title: Text(
              p.basename(t.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${t.sourceName} • ${t.path}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Transform.scale(
              scale: 1.2,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) => onToggle(t.path, v ?? false),
              ),
            ),
            onTap: () => onToggle(t.path, !isSelected),
          );
        },
      ),
    );
  }
}

class _TrackRow {
  const _TrackRow({
    required this.sourceName,
    required this.path,
    required this.missing,
  });

  final String sourceName;
  final String path;
  final bool missing;
}


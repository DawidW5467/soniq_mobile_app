import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'audio_controller.dart';
import 'i18n.dart';
import 'screens/settings.dart';
import 'metadata/lyric_parser.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.position,
    required this.onClose,
    required this.textColor,
    required this.activeColor,
    required this.onSeek,
  });

  final String lyrics;
  final Duration position;
  final VoidCallback onClose;
  final Color textColor;
  final Color activeColor;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No lyrics found', style: TextStyle(fontSize: 24, color: textColor)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      );
    }

    final parsed = LyricParser.parse(lyrics);
    final isSynced = parsed.isNotEmpty;

    if (!isSynced) {
      return Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 60, 40, 100),
            child: Center(
              child: Text(
                lyrics,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, height: 1.6, color: textColor),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, size: 32),
              onPressed: onClose,
            ),
          ),
        ],
      );
    }

    int activeIndex = -1;
    for (int i = 0; i < parsed.length; i++) {
      if (position >= parsed[i].time) {
        activeIndex = i;
      } else {
        break;
      }
    }

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return _SyncedLyricsList(
              lines: parsed,
              activeIndex: activeIndex,
              textColor: textColor,
              activeColor: activeColor,
              onSeek: onSeek,
            );
          },
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, size: 32),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

class _SyncedLyricsList extends StatefulWidget {
  const _SyncedLyricsList({
    required this.lines,
    required this.activeIndex,
    required this.textColor,
    required this.activeColor,
    required this.onSeek,
  });

  final List<LyricLine> lines;
  final int activeIndex;
  final Color textColor;
  final Color activeColor;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 86.0;
  static const double _listPadding = 24.0;
  final Map<int, double> _itemHeights = {};
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    if (widget.activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (widget.activeIndex != oldWidget.activeIndex && widget.activeIndex >= 0) {
      _scrollToActive();
    }
  }

  void _syncKeys() {
    if (_itemKeys.length == widget.lines.length) return;
    _itemKeys
      ..clear()
      ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
  }

  void _recordItemHeight(int index) {
    if (index < 0 || index >= _itemKeys.length) return;
    final ctx = _itemKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final height = box.size.height;
    final prev = _itemHeights[index];
    if (prev == height) return;
    _itemHeights[index] = height;
    if (index == widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  double _offsetForIndex(int index) {
    var offset = _listPadding;
    for (var i = 0; i < index; i++) {
      offset += _itemHeights[i] ?? _itemHeight;
    }
    return offset;
  }

  void _scrollToActive() {
    if (!_scrollController.hasClients || widget.activeIndex < 0) return;
    final viewportHeight = _scrollController.position.viewportDimension;
    final activeHeight = _itemHeights[widget.activeIndex] ?? _itemHeight;
    final itemTop = _offsetForIndex(widget.activeIndex);
    final target = itemTop - (viewportHeight - activeHeight) / 2;

    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: _listPadding),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final isActive = index == widget.activeIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) => _recordItemHeight(index));
        return Center(
          child: ConstrainedBox(
            key: _itemKeys[index],
            constraints: const BoxConstraints(minHeight: _itemHeight),
            child: InkWell(
              onTap: () => widget.onSeek(widget.lines[index].time),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isActive ? 34 : 24,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? widget.activeColor : widget.textColor.withValues(alpha: 0.6),
                  ),
                  child: Text(
                    widget.lines[index].text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CavaVisualizerPainter extends StatefulWidget {
  const CavaVisualizerPainter({
    super.key,
    required this.stream,
    required this.color,
  });

  final Stream<List<double>> stream;
  final Color color;

  @override
  State<CavaVisualizerPainter> createState() => _CavaVisualizerPainterState();
}

class _CavaVisualizerPainterState extends State<CavaVisualizerPainter> {
  List<double> _data = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen((data) {
      if (mounted) {
        setState(() => _data = data);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CavaPainter(_data, widget.color),
    );
  }
}

class _CavaPainter extends CustomPainter {
  _CavaPainter(this.data, this.color);

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxValue = data.reduce(max);
    if (maxValue <= 0) return;

    final center = size.center(Offset.zero);
    final shortest = min(size.width, size.height);

    final innerRadius = shortest * 0.42;
    final maxBarHeight = shortest * 0.20;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final angleStep = 2 * pi / data.length;
    final baseStroke = (2 * pi * innerRadius / data.length).clamp(3.0, 14.0);

    for (int i = 0; i < data.length; i++) {
      final value = (data[i] / maxValue).clamp(0.0, 1.0);
      if (value < 0.015) continue;

      final barH = value * maxBarHeight;
      final angle = i * angleStep - (pi / 2);

      final r1 = innerRadius;
      final r2 = innerRadius + barH;

      final p1 = Offset(center.dx + r1 * cos(angle), center.dy + r1 * sin(angle));
      final p2 = Offset(center.dx + r2 * cos(angle), center.dy + r2 * sin(angle));

      paint.strokeWidth = baseStroke;
      paint.color = color.withValues(alpha: (0.45 + 0.55 * value).clamp(0.0, 1.0));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CavaPainter oldDelegate) {
    return data != oldDelegate.data;
  }
}

class PlayerControlsPanel extends StatefulWidget {
  const PlayerControlsPanel({
    super.key,
    required this.audio,
    required this.audioState,
    required this.settingsController,
    required this.strings,
    required this.canOpenTrackList,
    required this.currentTrackPath,
    required this.onGoHome,
    required this.onOpenTrackList,
    required this.onOpenHistory,
    required this.onToggleVisualizer,
    required this.onToggleLyrics,
  });

  final AudioController audio;
  final AudioState audioState;
  final SettingsController? settingsController;
  final AppStrings strings;
  final bool canOpenTrackList;
  final String? currentTrackPath;
  final VoidCallback onGoHome;
  final VoidCallback onOpenTrackList;
  final VoidCallback onOpenHistory;
  final VoidCallback onToggleVisualizer;
  final VoidCallback onToggleLyrics;

  @override
  State<PlayerControlsPanel> createState() => _PlayerControlsPanelState();
}

class _PlayerControlsPanelState extends State<PlayerControlsPanel> {
  double? _seekPosition;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHighContrast = cs.brightness == Brightness.dark;
    final audioState = widget.audioState;

    final duration = audioState.duration;
    final position = audioState.position;
    final isPlaying = audioState.isPlaying;
    final hasPlaylist = widget.canOpenTrackList;

    final safeDurationSeconds = duration.inSeconds == 0 ? 1 : duration.inSeconds;
    final clampedPositionSeconds = position.inSeconds.clamp(0, safeDurationSeconds);

    final remaining = duration - position;
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;

    String fmt(Duration d) {
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    final progressBar = Column(
      children: [
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6.0,
            activeTrackColor: cs.primary.withValues(alpha: 0.95),
            inactiveTrackColor: cs.primaryContainer.withValues(alpha: 0.45),
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: _seekPosition != null ? 10 : 8,
              pressedElevation: 4,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            thumbColor: cs.primary,
            overlayColor: cs.primary.withValues(alpha: 0.18),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Listener(
            onPointerDown: (_) => setState(() => _seekPosition = null),
            onPointerUp: (_) async {
              final target = _seekPosition;
              setState(() => _seekPosition = null);
              if (target != null) {
                final targetPos = Duration(seconds: target.toInt());
                await widget.audio.seek(targetPos);
              }
            },
            child: Slider(
              value: _seekPosition != null
                  ? _seekPosition!
                  : clampedPositionSeconds.toDouble(),
              min: 0,
              max: safeDurationSeconds.toDouble(),
              onChanged: (value) => setState(() => _seekPosition = value),
              onChangeEnd: (value) async {
                final newPos = Duration(seconds: value.toInt());
                await widget.audio.seek(newPos);
                setState(() => _seekPosition = null);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fmt(_seekPosition != null
                    ? Duration(seconds: _seekPosition!.toInt())
                    : position),
                style: TextStyle(fontSize: 16, color: cs.onSurface),
              ),
              Text(
                fmt(_seekPosition != null
                    ? duration - Duration(seconds: _seekPosition!.toInt())
                    : safeRemaining),
                style: TextStyle(fontSize: 16, color: cs.onSurface),
              ),
            ],
          ),
        ),
      ],
    );

    final volumeRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          const Icon(Icons.volume_down),
          Expanded(
            child: Slider(
              value: audioState.volume.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: (value) => widget.audio.setVolume(value),
            ),
          ),
          const Icon(Icons.volume_up),
        ],
      ),
    );

    final buttonsRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.settingsController?.simpleControls == true)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 20),
              ),
              onPressed: widget.onGoHome,
              child: Text(widget.strings.get('home')),
            )
          else
            ElevatedButton.icon(
              onPressed: widget.onGoHome,
              icon: const Icon(Icons.home),
              label: Text(widget.strings.get('home'), style: const TextStyle(fontSize: 18)),
            ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              if (hasPlaylist) {
                widget.onOpenTrackList();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.strings.get('noPlaylistLoaded'))),
                );
              }
            },
            icon: const Icon(Icons.queue_music),
            label: Text(widget.strings.get('trackList'), style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: widget.onOpenHistory,
            icon: const Icon(Icons.history),
            label: Text(widget.strings.get('history'), style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: widget.onToggleVisualizer,
            icon: const Icon(Icons.graphic_eq),
            label: Text(widget.strings.get('visualizer'), style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: widget.onToggleLyrics,
            icon: const Icon(Icons.lyrics),
            label: Text(widget.strings.get('lyrics'), style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );

    final controlsRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 22),
                foregroundColor: audioState.isShuffleEnabled
                    ? (isHighContrast ? cs.onPrimary : cs.onPrimaryContainer)
                    : cs.onSurface,
                backgroundColor: audioState.isShuffleEnabled
                    ? (isHighContrast ? cs.onSurface : cs.primaryContainer)
                    : null,
              ),
              onPressed: widget.audio.toggleShuffle,
              child: Text(widget.strings.get('controlShuffle')),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: Icon(Icons.shuffle, color: audioState.isShuffleEnabled ? cs.primary : null),
              iconSize: 38,
              onPressed: widget.audio.toggleShuffle,
            ),
          ],
          const SizedBox(width: 8),
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 22),
              ),
              onPressed: () => widget.audio.back(),
              child: Text(widget.strings.get('controlPrevious')),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 60, minHeight: 60),
              icon: const Icon(Icons.skip_previous),
              iconSize: 54,
              onPressed: () => widget.audio.back(),
            ),
          ],
          const SizedBox(width: 10),
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                if (isPlaying) {
                  widget.audio.pause();
                } else {
                  widget.audio.play();
                }
              },
              child: Text(
                isPlaying ? widget.strings.get('controlPause') : widget.strings.get('controlPlay'),
              ),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 84, minHeight: 84),
              icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
              iconSize: 86,
              onPressed: () {
                if (isPlaying) {
                  widget.audio.pause();
                } else {
                  widget.audio.play();
                }
              },
            ),
          ],
          const SizedBox(width: 10),
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 22),
              ),
              onPressed: () => widget.audio.next(),
              child: Text(widget.strings.get('controlNext')),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 60, minHeight: 60),
              icon: const Icon(Icons.skip_next),
              iconSize: 54,
              onPressed: () => widget.audio.next(),
            ),
          ],
          const SizedBox(width: 8),
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 22),
                foregroundColor: audioState.loopMode != LoopMode.off
                    ? (isHighContrast ? cs.onPrimary : cs.onPrimaryContainer)
                    : cs.onSurface,
                backgroundColor: audioState.loopMode != LoopMode.off
                    ? (isHighContrast ? cs.onSurface : cs.primaryContainer)
                    : null,
              ),
              onPressed: widget.audio.cycleLoopMode,
              child: Text(
                audioState.loopMode == LoopMode.one
                    ? widget.strings.get('controlRepeatOne')
                    : widget.strings.get('controlRepeat'),
              ),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: Icon(
                audioState.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: audioState.loopMode != LoopMode.off ? cs.primary : null,
              ),
              iconSize: 38,
              onPressed: widget.audio.cycleLoopMode,
            ),
          ],
          const SizedBox(width: 8),
          if (widget.settingsController?.simpleControls == true) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 22),
              ),
              onPressed: widget.audio.stop,
              child: Text(widget.strings.get('controlStop')),
            ),
          ] else ...[
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              icon: const Icon(Icons.stop),
              iconSize: 40,
              onPressed: widget.audio.stop,
            ),
          ],
          const SizedBox(width: 8),
          ValueListenableBuilder<Set<String>>(
            valueListenable: widget.audio.likedPaths,
            builder: (context, liked, _) {
              final path = widget.currentTrackPath;
              final isLiked = path != null && liked.contains(path);
              if (widget.settingsController?.simpleControls == true) {
                return TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 22),
                    foregroundColor: isLiked ? cs.primary : cs.onSurface,
                  ),
                  onPressed: path == null ? null : () => widget.audio.toggleLike(path),
                  child: Text(isLiked ? widget.strings.get('liked') : widget.strings.get('like')),
                );
              }
              return IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
                iconSize: 40,
                color: isLiked ? cs.primary : null,
                onPressed: path == null ? null : () => widget.audio.toggleLike(path),
              );
            },
          ),
        ],
      ),
    );

    return Column(
      children: [
        progressBar,
        volumeRow,
        buttonsRow,
        controlsRow,
      ],
    );
  }
}

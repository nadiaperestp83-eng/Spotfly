import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/player_notifier.dart';

/// Componente PURO: só lê PlayerState. Não sabe o que é YouTube,
/// Jamendo, nem que "sourceId" existe.
class PlayerWidget extends ConsumerWidget {
  const PlayerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerNotifierProvider);
    final track = state.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(track.artworkUrl, width: 48, height: 48, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(track.artist, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () => ref.read(playerNotifierProvider.notifier).togglePlayPause(),
        ),
      ],
    );
  }
}

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';

import '../../../features/home/state/recently_played_notifier.dart';
import '../../player/player_controller.dart';

/// Fileira "Recent played": até 2 cards grandes com as últimas músicas
/// tocadas (fonte: recentlyPlayedProvider, que lê a Hive box "LIBRP" já
/// mantida por PlayerController._addToRP). Some sozinha se ainda não
/// houver nenhuma música tocada (ex.: instalação nova).
class RecentPlayedRow extends ConsumerWidget {
  const RecentPlayedRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);

    return recentlyPlayedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        final cards = items.take(2).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24, right: 10),
          child: SizedBox(
            height: 90,
            child: Row(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _RecentPlayedCard(song: cards[i])),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentPlayedCard extends StatelessWidget {
  const _RecentPlayedCard({required this.song});
  final MediaItem song;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final cardColor = Theme.of(context).cardColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: cardColor,
        child: InkWell(
          onTap: () => playerController.pushSongToQueue(song),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: song.artUri.toString(),
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => ColoredBox(
                  color: cardColor,
                ),
              ),
              // Sombreado escuro por baixo pra garantir contraste do
              // título independente da cor da capa (funciona em
              // qualquer tema, claro ou escuro).
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.75),
                      Colors.black.withOpacity(0.15),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

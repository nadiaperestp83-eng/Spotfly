import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';

import '../../../features/home/state/recently_played_notifier.dart';
import '../../../models/playling_from.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';

/// Fileira "Recém tocadas": lista horizontal rolável de cards grandes
/// (capa em cima, título + artista embaixo) — mesmo layout de card do
/// print de referência da Apple Music ("Friends Are Listening To"),
/// adaptado pra não depender de nenhum recurso social que o app não
/// tem: sem foto de "amigo" sobreposta, só a capa da música mesmo.
///
/// Fonte: recentlyPlayedProvider, que lê a Hive box "LIBRP" já mantida
/// por PlayerController._addToRP — mesma lógica de sempre, só a
/// apresentação mudou (de 2 cards com texto sobreposto à capa, fixos,
/// pra uma fileira rolável maior com legenda abaixo da capa).
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

        final cards = items.take(10).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  "recentlyPlayed".tr,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _RecentPlayedCard(song: cards[index]),
                ),
              ),
            ],
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

    return SizedBox(
      width: 120,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => playerController.playPlayListSong(
          [song],
          0,
          playfrom: PlaylingFrom(
            type: PlaylingFromType.SELECTION,
            name: "Recent played",
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImageWidget(song: song, size: 120),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              "${song.artist}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.grey[600]
                      : Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}

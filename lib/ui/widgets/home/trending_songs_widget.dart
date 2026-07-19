import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/playling_from.dart';
import '../../../models/quick_picks.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../songinfo_bottom_sheet.dart';

/// Seção "Mais tocadas" (Trending/YouTube): FIXA na Home, sempre
/// visível pra todo mundo — antes essa lista só aparecia quando o
/// usuário escolhia "Trending" no seletor "Discover" das Configurações
/// (o que fazia ela sumir pra quem estava em "Quick Picks", o padrão).
/// Agora é buscada direto em HomeScreenController.loadTrendingSongs,
/// independente desse seletor.
///
/// Mesmo estilo visual do card "Recommended for you" (card arredondado
/// + título com ícone + botão de "tocar tudo"), só que com numeração
/// de posição no ranking em vez de capa circular, pra reforçar a
/// leitura de "chart".
class TrendingSongsWidget extends StatelessWidget {
  const TrendingSongsWidget({
    super.key,
    required this.content,
    this.isLoading = false,
  });
  final QuickPicks content;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && content.songList.isEmpty) return const SizedBox.shrink();

    final playerController = Get.find<PlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, right: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.trending_up_rounded,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "trending".tr,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (content.songList.isNotEmpty)
                  IconButton(
                    tooltip: "play".tr,
                    icon: CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.primary,
                      child: Icon(Icons.play_arrow,
                          color: colorScheme.onPrimary, size: 20),
                    ),
                    onPressed: () {
                      playerController.playPlayListSong(
                        List<MediaItem>.from(content.songList),
                        0,
                        playfrom: PlaylingFrom(
                          type: PlaylingFromType.SELECTION,
                          name: content.title,
                        ),
                      );
                    },
                  ),
              ],
            ),
            if (isLoading && content.songList.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: content.songList.length,
                itemBuilder: (context, index) {
                  final song = content.songList[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 4, right: 8),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            "${index + 1}",
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ImageWidget(song: song, size: 50),
                      ],
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      "${song.artist}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    trailing: IconButton(
                      splashRadius: 20,
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showSongInfo(context, song),
                    ),
                    onTap: () => playerController.playPlayListSong(
                      List<MediaItem>.from(content.songList),
                      index,
                      playfrom: PlaylingFrom(
                        type: PlaylingFromType.SELECTION,
                        name: content.title,
                      ),
                    ),
                    onLongPress: () => _showSongInfo(context, song),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSongInfo(BuildContext context, MediaItem song) {
    final playerController = Get.find<PlayerController>();
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: playerController.homeScaffoldkey.currentState!.context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(song),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }
}

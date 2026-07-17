import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/playling_from.dart';
import '../../../models/quick_picks.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../songinfo_bottom_sheet.dart';

/// Seção "Recommended for you": card cinza arredondado (Theme.cardColor,
/// igual ao usado em RecentPlayedRow) com lista de músicas cujas capas
/// são avatares circulares — visual pedido explicitamente pelo usuário,
/// diferente do quadrado com cantos de 8dp usado no resto do app.
///
/// Fonte dos dados: HomeScreenController.recommendedForYou, que combina
/// o histórico local (Hive "LIBRP") como semente com a API de músicas
/// relacionadas (ver home_screen_controller.dart -> loadRecommendedForYou).
class RecommendedForYouWidget extends StatelessWidget {
  const RecommendedForYouWidget({
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
                      Icon(Icons.auto_awesome_rounded,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "recommendedForYou".tr,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 18),
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
                    contentPadding: const EdgeInsets.only(left: 0, right: 8),
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      child: Center(
                        child: ImageWidget(
                          song: song,
                          size: 50,
                          forceCircle: true,
                        ),
                      ),
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

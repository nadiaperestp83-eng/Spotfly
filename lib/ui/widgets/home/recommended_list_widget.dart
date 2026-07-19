import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/playling_from.dart';
import '../../../models/quick_picks.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../songinfo_bottom_sheet.dart';

/// Mesmo conteúdo que antes ia pra QuickPicksWidget (grid horizontal),
/// só que agora em lista vertical com botão de "tocar tudo" — layout
/// pedido no print de referência. As outras seções horizontais da Home
/// (Trending, Top Music Videos etc.) continuam exatamente onde estavam,
/// sem nenhuma mudança.
class RecommendedListWidget extends StatelessWidget {
  const RecommendedListWidget({super.key, required this.content});
  final QuickPicks content;

  @override
  Widget build(BuildContext context) {
    if (content.songList.isEmpty) return const SizedBox.shrink();

    final playerController = Get.find<PlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  content.title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: "play".tr,
                icon: CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.primary,
                  child: Icon(Icons.play_arrow, color: colorScheme.onPrimary),
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
          const SizedBox(height: 5),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: content.songList.length,
            itemBuilder: (context, index) {
              final song = content.songList[index];
              return ListTile(
                contentPadding: const EdgeInsets.only(left: 5),
                leading: ImageWidget(song: song, size: 50),
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

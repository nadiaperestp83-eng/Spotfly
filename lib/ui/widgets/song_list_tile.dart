import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../models/playlist.dart';
import '../player/player_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'add_to_playlist.dart';
import 'image_widget.dart';
import 'snackbar.dart';
import 'songinfo_bottom_sheet.dart';

class SongListTile extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const SongListTile(
      {super.key,
      this.onTap,
      required this.song,
      this.playlist,
      this.isPlaylistOrAlbum = false,
      this.thumbReplacementWithIndex = false,
      this.index});
  final Playlist? playlist;
  final MediaItem song;
  final VoidCallback? onTap;
  final bool isPlaylistOrAlbum;

  /// Valid for Album songs
  final bool thumbReplacementWithIndex;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Listener(
        onPointerDown: (PointerDownEvent event) {
          if (event.buttons == kSecondaryMouseButton) {
            //show songinfobotomsheet
            showModalBottomSheet(
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
              ),
              isScrollControlled: true,
              context: playerController.homeScaffoldkey.currentState!.context,
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) => SongInfoBottomSheet(
                song,
                playlist: playlist,
              ),
            ).whenComplete(() => Get.delete<SongInfoController>());
          }
        },
        child: Slidable(
          enabled:
              Get.find<SettingsScreenController>().slidableActionEnabled.isTrue,
          startActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) {
                showDialog(
                  context: context,
                  builder: (context) => AddToPlaylist([song]),
                ).whenComplete(() => Get.delete<AddToPlaylistController>());
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.playlist_add,
              //label: 'Add to playlist',
            ),
            if (playlist != null && !playlist!.isCloudPlaylist)
              SlidableAction(
                onPressed: (context) {
                  removeSongFromPlaylist(song, playlist!);
                },
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
                icon: Icons.delete,
                //label: 'delete',
              ),
          ]),
          endActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) {
                playerController.enqueueSong(song).whenComplete(() {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "songEnqueueAlert".tr,
                      size: SanckBarSize.MEDIUM));
                });
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.merge,
              //label: 'Enqueue',
            ),
            SlidableAction(
              onPressed: (context) {
                playerController.playNext(song);
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context, "${"playnextMsg".tr} ${(song).title}",
                    size: SanckBarSize.BIG));
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.next_plan_outlined,
              //label: 'Play Next',
            ),
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
            onTap: onTap,
            onLongPress: () async {
              showModalBottomSheet(
                constraints: const BoxConstraints(maxWidth: 500),
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(10.0)),
                ),
                isScrollControlled: true,
                context: playerController.homeScaffoldkey.currentState!.context,
                //constraints: BoxConstraints(maxHeight:Get.height),
                barrierColor: Colors.transparent.withAlpha(100),
                builder: (context) => SongInfoBottomSheet(
                  song,
                  playlist: playlist,
                ),
              ).whenComplete(() => Get.delete<SongInfoController>());
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            // Estilo Apple Music: capa/ícone alinhado à esquerda com
            // cantos levemente arredondados (ver ImageWidget._radius),
            // título em negrito 16sp, autor em cinza 14sp, ação
            // discreta (só ícone, sem fundo colorido) à direita.
            leading: thumbReplacementWithIndex
                ? SizedBox(
                    width: 27.5,
                    height: 55,
                    child: Center(
                      child: Text(
                        "$index.",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                : SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: ImageWidget(
                        size: 48,
                        song: song,
                        forceCircle: false,
                      ),
                    ),
                  ),
            title: Marquee(
              delay: const Duration(milliseconds: 300),
              duration: const Duration(seconds: 5),
              id: song.title.hashCode.toString(),
              child: Text(
                song.title.length > 50
                    ? song.title.substring(0, 50)
                    : song.title,
                maxLines: 1,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Theme.of(context).textTheme.titleMedium?.color,
                ),
              ),
            ),
            subtitle: Text(
              "${song.artist}",
              maxLines: 1,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.grey[600]
                    : const Color(0xFFB3B3B3),
              ),
            ),
            trailing: SizedBox(
              width: Get.size.width > 800 ? 80 : 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPlaylistOrAlbum)
                        Obx(() =>
                            playerController.currentSong.value?.id == song.id
                                ? Icon(
                                    Icons.equalizer,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary,
                                    size: 18,
                                  )
                                : const SizedBox.shrink()),
                      Text(
                        song.extras!['length'] ?? "",
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  if (GetPlatform.isDesktop)
                    IconButton(
                        splashRadius: 20,
                        onPressed: () {
                          showModalBottomSheet(
                            constraints: const BoxConstraints(maxWidth: 500),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10.0)),
                            ),
                            isScrollControlled: true,
                            context: playerController
                                .homeScaffoldkey.currentState!.context,
                            //constraints: BoxConstraints(maxHeight:Get.height),
                            barrierColor: Colors.transparent.withAlpha(100),
                            builder: (context) => SongInfoBottomSheet(
                              song,
                              playlist: playlist,
                            ),
                          ).whenComplete(
                              () => Get.delete<SongInfoController>());
                        },
                        icon: Icon(Icons.more_vert,
                            size: 20,
                            color: Theme.of(context).brightness ==
                                    Brightness.light
                                ? Colors.grey[500]
                                : Colors.grey[400]))
                ],
              ),
            ),
          ),
        )));
  }
}

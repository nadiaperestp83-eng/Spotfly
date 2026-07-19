import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import 'image_widget.dart';

class ContentListItem extends StatelessWidget {
  const ContentListItem(
      {super.key, required this.content, this.isLibraryItem = false});

  ///content will be of Type class Album or Playlist
  final dynamic content;
  final bool isLibraryItem;

  @override
  Widget build(BuildContext context) {
    final isAlbum = content.runtimeType.toString() == "Album";
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () {
        if (isAlbum) {
          Get.toNamed(ScreenNavigationSetup.albumScreen,
              id: ScreenNavigationSetup.id, arguments:(content, content.browseId));
          return;
        }
        Get.toNamed(ScreenNavigationSetup.playlistScreen,
            id: ScreenNavigationSetup.id,
            arguments: [content, content.playlistId]);
      },
      child: Container(
        width: 112,
        height: 170,
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            isAlbum
                ? ImageWidget(
                    size: 104,
                    album: content,
                  )
                : content.isCloudPlaylist ||
                        !(content.playlistId == 'LIBRP' ||
                            content.playlistId == 'LIBFAV' ||
                            content.playlistId == 'SongsCache' ||
                            content.playlistId == 'SongDownloads')
                    ? SizedBox.square(
                        dimension: 104,
                        child: Stack(
                          children: [
                            ImageWidget(
                              size: 104,
                              playlist: content,
                            ),
                            if (content.isPipedPlaylist)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Container(
                                    height: 18,
                                    width: 18,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    child: Center(
                                        child: Text(
                                      "P",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(fontSize: 14),
                                    )),
                                  ),
                                ),
                              ),
                            if (!content.isCloudPlaylist)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Container(
                                    height: 18,
                                    width: 18,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    child: Center(
                                        child: Text(
                                      "L",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(fontSize: 14),
                                    )),
                                  ),
                                ),
                              )
                          ],
                        ),
                      )
                    : Container(
                        height: 104,
                        width: 104,
                        decoration: BoxDecoration(
                            color: Theme.of(context).primaryColorLight,
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(
                            child: Icon(
                          content.playlistId == 'LIBRP'
                              ? Icons.history
                              : content.playlistId == 'LIBFAV'
                                  ? Icons.favorite
                                  : content.playlistId == 'SongsCache'
                                      ? Icons.flight
                                      : Icons.download,
                          color: Colors.white,
                          size: 40,
                        ))),
            const SizedBox(height: 6),
            Text(
              content.title,
              // overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              isAlbum
                  ? isLibraryItem
                      ? ""
                      : "${content.artists[0]['name'] ?? ""} | ${content.year ?? ""}"
                  : isLibraryItem
                      ? ""
                      : content.description ?? "",
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

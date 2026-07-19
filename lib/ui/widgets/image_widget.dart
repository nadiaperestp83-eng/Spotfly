import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/models/artist.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

class ImageWidget extends StatelessWidget {
  const ImageWidget({
    super.key,
    this.song,
    this.playlist,
    this.album,
    this.artist,
    required this.size,
    this.isPlayerArtImage = false,
    this.forceCircle = false,
  });
  final MediaItem? song;
  final Playlist? playlist;
  final Album? album;
  final bool isPlayerArtImage;
  final Artist? artist;
  final double size;

  /// Quando true, força o formato circular mesmo para song/album/playlist
  /// (que por padrão usam BorderRadius.circular(8)). Usado nas listas
  /// de músicas que devem imitar o layout circular do Spotify.
  final bool forceCircle;

  /// Raio de borda: 20 pra capa da tela "Now Playing" (pedido explícito
  /// do redesign estilo Apple Music — BorderRadius.circular(20)), 8
  /// pro resto (listas, mini player) — mantém o padrão existente.
  double get _radius => isPlayerArtImage ? 20 : 8;

  @override
  Widget build(BuildContext context) {
    String imageUrl = song != null
        ? song!.artUri.toString()
        : playlist != null
            ? playlist!.thumbnailUrl
            : album != null
                ? album!.thumbnailUrl
                : artist != null
                    ? artist!.thumbnailUrl
                    : "";
    // String cacheKey = song != null
    //     ? "${song!.id}_song"
    //     : playlist != null
    //         ? "${playlist!.playlistId}_playlist"
    //         : album != null
    //             ? "${album!.browseId}_album"
    //             : artist != null
    //                 ? "${artist!.browseId}_artist"
    //                 : "";

    /// only valid for offline songs
    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").contains("file");

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // artist != null OU forceCircle == true renderiza um círculo
        // perfeito. Caso contrário, cantos ~8dp (padrão Spotify para
        // álbuns/playlists/músicas).
        shape: (artist != null || forceCircle)
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius:
            (artist != null || forceCircle) ? null : BorderRadius.circular(_radius),
      ),
      child: offlineAvailable
          ? Image.file(
              File(
                  "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
              height: size,
              width: size,
              fit: BoxFit.cover,
            )
          : CachedNetworkImage(
              height: size,
              width: size,
              memCacheHeight: (song != null && !isPlayerArtImage) ? 140 : null,
              //memCacheWidth: (song != null && !isPlayerArtImage)? 140 : null,
              //cacheKey: cacheKey,
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) {
                return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      shape: (artist != null || forceCircle)
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: (artist != null || forceCircle)
                          ? null
                          : BorderRadius.circular(_radius),
                    ),
                    child: Image.asset(
                        "assets/icons/${song != null ? "song" : artist != null ? "artist" : "album"}.png"));
              },
              progressIndicatorBuilder: ((_, __, ___) => Shimmer.fromColors(
                  baseColor: Colors.grey[500]!,
                  highlightColor: Colors.grey[300]!,
                  enabled: true,
                  direction: ShimmerDirection.ltr,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: (artist != null || forceCircle)
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: (artist != null || forceCircle)
                          ? null
                          : BorderRadius.circular(_radius),
                      color: Colors.white54,
                    ),
                  ))),
            ),
    );
  }
}

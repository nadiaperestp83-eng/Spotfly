import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/components/backgroud_image.dart';

import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import 'glass_player_card.dart';

class GesturePlayer extends StatelessWidget {
  const GesturePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Stack(
      children: [
        GestureDetector(
          /// Full screen Background image is acting as album art
          child: const BackgroudImage(),
          onHorizontalDragEnd: (DragEndDetails details) {
            if (details.primaryVelocity! < 0) {
              playerController.next();
            } else if (details.primaryVelocity! > 0) {
              playerController.prev();
            }
          },
          onDoubleTap: () {
            playerController.playPause();
          },
          onLongPress: () {
            showModalBottomSheet(
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
              ),
              isScrollControlled: true,
              context: playerController.homeScaffoldkey.currentState!.context,
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) => SongInfoBottomSheet(
                playerController.currentSong.value!,
                calledFromPlayer: true,
              ),
            ).whenComplete(() => Get.delete<SongInfoController>());
          },
        ),
        IgnorePointer(
          child: Align(
            child: Center(
              child: Obx(
                () => FadeTransition(
                  opacity: playerController.gesturePlayerStateAnimation!,
                  child: playerController.gesturePlayerVisibleState.value == 2
                      ? const SizedBox.shrink()
                      : Icon(
                          playerController.gesturePlayerVisibleState.value == 1
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 180,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ),
        // Card de vidro claro (glassmorphism) com capa, título/artista,
        // controles anterior/play-pause/próxima, barra de progresso, e
        // fileira de ícones (letra/favoritar/compartilhar) — ver
        // glass_player_card.dart.
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: Get.mediaQuery.padding.bottom != 0
                    ? Get.mediaQuery.padding.bottom + 10
                    : 20,
                left: 20,
                right: 20),
            child: const GlassPlayerCard(),
          ),
        ),
        // absorb pointer to prevent the next,prev gesture from being triggered when the user tries to switch app
        Align(
          alignment: Alignment.bottomCenter,
          child: AbsorbPointer(
            child: SizedBox(
              height: Get.mediaQuery.padding.bottom + 20,
              child: Container(),
            ),
          ),
        )
      ],
    );
  }
}

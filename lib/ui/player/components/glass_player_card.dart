import 'dart:ui';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../widgets/image_widget.dart';
import '../player_controller.dart';
import 'lyrics_widget.dart';

/// Card de player em vidro fosco claro (glassmorphism), no estilo da
/// referência enviada pela usuária: card branco translúcido flutuando
/// sobre a arte do álbum desfocada de fundo, com capa arredondada,
/// título/artista, botão de play/pause circular preenchido (cor de
/// destaque), setas de anterior/próxima, barra de progresso com
/// tempo, e uma fileira de 3 ícones (letra/favoritar/compartilhar)
/// abaixo do card.
///
/// SÓ o player de gestos (GesturePlayer) usa esse card — decisão
/// explícita da usuária (print enviado era desse modo). O player
/// padrão (StandardPlayer) e o resto do app continuam com o tema
/// escuro de sempre.
///
/// Toda a funcionalidade aqui é reaproveitada do que já existia:
/// - play/pause/próxima/anterior: playerController (mesmos métodos do
///   PlayerControlWidget).
/// - ícone de nota = alterna letra da música (playerController.showLyrics(),
///   mesmo flag usado por AlbumArtNLyrics no player padrão).
/// - ícone de coração = favoritar (playerController.toggleFavourite,
///   mesmo do player padrão).
/// - ícone de compartilhar = mesmo link do YouTube usado em
///   songinfo_bottom_sheet.dart.
class GlassPlayerCard extends StatelessWidget {
  const GlassPlayerCard({super.key});

  // Cor de destaque do botão de play (mesmo tom rosa/vermelho da
  // referência enviada).
  static const _accentColor = Color(0xFFE8305A);

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final size = MediaQuery.of(context).size;
    final artSize = size.width * 0.5;

    return Obx(() {
      final song = playerController.currentSong.value;
      if (song == null) return const SizedBox.shrink();

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Card de vidro claro ----
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.5), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Capa do álbum (ou letra da música, se alternado)
                    GestureDetector(
                      onTap: playerController.showLyrics,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: playerController.showLyricsflag.isTrue
                            ? Container(
                                height: artSize,
                                width: artSize,
                                color: Colors.black87,
                                child: const LyricsWidget(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 20),
                                ),
                              )
                            : ImageWidget(
                                size: artSize,
                                song: song,
                                isPlayerArtImage: true,
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Título + artista (texto escuro, card é claro)
                    Marquee(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(seconds: 10),
                      id: "${song.id}_glass_title",
                      child: Text(
                        song.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Marquee(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(seconds: 10),
                      id: "${song.id}_glass_subtitle",
                      child: Text(
                        song.artist ?? "",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFF1A1A2E).withOpacity(0.5),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Anterior / Play-Pause / Próxima
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 34,
                          color: const Color(0xFF1A1A2E),
                          icon: const Icon(Icons.chevron_left),
                          onPressed: playerController.prev,
                        ),
                        const SizedBox(width: 28),
                        _GlassPlayPauseButton(
                            playerController: playerController),
                        const SizedBox(width: 28),
                        _NextButton(playerController: playerController),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Barra de progresso com tempo
                    GetX<PlayerController>(builder: (controller) {
                      return ProgressBar(
                        thumbRadius: 6,
                        barHeight: 3.5,
                        baseBarColor: const Color(0xFF1A1A2E).withOpacity(0.15),
                        bufferedBarColor:
                            const Color(0xFF1A1A2E).withOpacity(0.25),
                        progressBarColor: _accentColor,
                        thumbColor: _accentColor,
                        timeLabelTextStyle: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        progress: controller.progressBarStatus.value.current,
                        total: controller.progressBarStatus.value.total,
                        buffered: controller.progressBarStatus.value.buffered,
                        onSeek: controller.seek,
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // ---- Fileira de ícones fora do card (letra / favoritar / compartilhar) ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 26,
                color: Colors.white,
                icon: Obx(() => Icon(playerController.showLyricsflag.isTrue
                    ? Icons.music_note
                    : Icons.music_note_outlined)),
                onPressed: playerController.showLyrics,
              ),
              IconButton(
                iconSize: 26,
                color: Colors.white,
                icon: Obx(() => Icon(
                      playerController.isCurrentSongFav.isTrue
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: playerController.isCurrentSongFav.isTrue
                          ? _accentColor
                          : Colors.white,
                    )),
                onPressed: playerController.toggleFavourite,
              ),
              IconButton(
                iconSize: 26,
                color: Colors.white,
                icon: const Icon(Icons.share_outlined),
                onPressed: () => Share.share(
                    "https://youtube.com/watch?v=${song.id}"),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _GlassPlayPauseButton extends StatelessWidget {
  const _GlassPlayPauseButton({required this.playerController});
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(builder: (controller) {
      final isPlaying = controller.buttonState.value == PlayButtonState.playing;
      final isLoading = controller.buttonState.value == PlayButtonState.loading;
      return Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GlassPlayerCard._accentColor,
          boxShadow: [
            BoxShadow(
              color: GlassPlayerCard._accentColor.withOpacity(0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : IconButton(
                iconSize: 30,
                color: Colors.white,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: isPlaying ? controller.pause : controller.play,
              ),
      );
    });
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.playerController});
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isLastSong = playerController.currentQueue.isEmpty ||
          (!(playerController.isShuffleModeEnabled.isTrue ||
                  playerController.isQueueLoopModeEnabled.isTrue) &&
              (playerController.currentQueue.last.id ==
                  playerController.currentSong.value?.id));
      return IconButton(
        iconSize: 34,
        color: isLastSong
            ? const Color(0xFF1A1A2E).withOpacity(0.25)
            : const Color(0xFF1A1A2E),
        icon: const Icon(Icons.chevron_right),
        onPressed: isLastSong ? null : playerController.next,
      );
    });
  }
}

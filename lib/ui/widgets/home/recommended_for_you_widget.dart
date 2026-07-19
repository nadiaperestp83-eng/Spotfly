import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/playling_from.dart';
import '../../../models/quick_picks.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';

/// Seção "Recommended for you": card colagem grande estilo "New Music
/// Mix" da Apple Music — um bloco de texto em destaque à esquerda +
/// grade de capas à direita + botão de play grande no canto. Pedido
/// explícito do usuário pra reproduzir esse card de referência.
///
/// A lógica não mudou: mesma fonte de dados
/// (HomeScreenController.recommendedForYou) e o mesmo
/// playPlayListSong() de sempre — só a apresentação virou colagem em
/// vez de lista vertical de linhas.
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
    final songs = content.songList;

    void playAll() {
      if (songs.isEmpty) return;
      playerController.playPlayListSong(
        List<MediaItem>.from(songs),
        0,
        playfrom: PlaylingFrom(
          type: PlaylingFromType.SELECTION,
          name: content.title,
        ),
      );
    }

    /// Pega a capa do índice [i], repetindo a lista se ela for menor
    /// que o número de espaços da colagem (ex.: só 2 recomendações).
    MediaItem coverAt(int i) => songs[i % songs.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "recommendedForYou".tr,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (isLoading && songs.isEmpty)
            SizedBox(
              height: 170,
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colorScheme.secondary),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: playAll,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 170,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Bloco de destaque (texto), estilo "New Music
                      // Mix" — usa a cor de destaque do tema pra ficar
                      // consistente entre claro e escuro.
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.secondary,
                                colorScheme.secondary.withOpacity(0.75),
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "recommendedForYou".tr,
                                maxLines: 3,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  height: 1.15,
                                ),
                              ),
                              const Text(
                                "Feito pra você",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      // Colagem de capas (2x2) — cada item já toca a
                      // playlist inteira a partir dele.
                      if (songs.isNotEmpty) ...[
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Expanded(
                                  child: ImageWidget(
                                      song: coverAt(0), size: 80)),
                              const SizedBox(height: 3),
                              Expanded(
                                  child: ImageWidget(
                                      song: coverAt(1), size: 80)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          flex: 2,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ImageWidget(song: coverAt(2), size: 90),
                              // Botão de play grande no canto,
                              // sobreposto à última capa — mesmo papel
                              // do círculo vermelho do print.
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Material(
                                  color: colorScheme.secondary,
                                  shape: const CircleBorder(),
                                  elevation: 3,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: playAll,
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(Icons.play_arrow,
                                          color: Colors.white, size: 24),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

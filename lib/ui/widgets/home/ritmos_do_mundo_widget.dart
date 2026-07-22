import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/playling_from.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../songinfo_bottom_sheet.dart';

/// "Ritmos do Mundo": carrossel horizontal de músicas REAIS (capa,
/// título, artista) buscadas no YouTube por palavras-chave de estilos/
/// culturas que não costumam aparecer nos feeds "top hits" comuns
/// (árabe, cigana, flamenco, dabke, tango, italiana, fado). Ocupa o
/// lugar que era do antigo "Minutos de Reflexão" na Home — ver
/// HomeScreenController.loadRitmosDoMundo.
///
/// Ao contrário do AudioNarrativeWidget (usado por Contos da Noite/
/// Poesia Sonora, que gera uma capa/gradiente porque a fonte —
/// Internet Archive — quase nunca tem capa decente nos metadados),
/// aqui a fonte é o YouTube (mesmo motor da seção "Mais tocadas" e da
/// busca manual), então cada card usa a capa REAL do vídeo via
/// ImageWidget, igual às outras seções de música da Home.
class RitmosDoMundoWidget extends StatelessWidget {
  const RitmosDoMundoWidget({
    super.key,
    required this.sectionTitle,
    required this.items,
    this.isLoading = false,
  });

  final String sectionTitle;
  final List<MediaItem> items;
  final bool isLoading;

  static const double _cardSize = 120;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 12),
            child: Text(
              sectionTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          SizedBox(
            height: _cardSize + 56,
            child: isLoading && items.isEmpty
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _RitmoCard(
                          items: items,
                          index: index,
                          sectionTitle: sectionTitle,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RitmoCard extends StatelessWidget {
  const _RitmoCard({
    required this.items,
    required this.index,
    required this.sectionTitle,
  });

  final List<MediaItem> items;
  final int index;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final song = items[index];
    final playerController = Get.find<PlayerController>();
    return GestureDetector(
      onTap: () => playerController.playPlayListSong(
        List<MediaItem>.from(items),
        index,
        playfrom: PlaylingFrom(
          type: PlaylingFromType.SELECTION,
          name: sectionTitle,
        ),
      ),
      onLongPress: () => _showSongInfo(context, song),
      child: SizedBox(
        width: RitmosDoMundoWidget._cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ImageWidget(
                song: song,
                size: RitmosDoMundoWidget._cardSize,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              "${song.artist}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
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

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/player_notifier.dart';
import '../../../core/riverpod/app_provider_container.dart';
import '../../../features/search/data/track_media_item_mapper.dart';

/// Carrossel horizontal reutilizado pelas 3 seções narrativas da Home
/// ("Minutos de Reflexão", "Contos da Noite", "Poesia Sonora") — mesmo
/// estilo de card (tamanho, cantos, gradiente + título embaixo) do
/// carrossel "Estações de Rádio Popular", pra manter a identidade
/// visual consistente ("estilo carrossel Spotify").
///
/// As faixas vêm do Internet Archive (ver InternetArchiveSource) e
/// quase nunca têm uma capa de álbum decente/moderna nos metadados —
/// por isso, em vez de tentar carregar `artUri` (que normalmente é
/// nulo ou uma capa de livro escaneada antiga), cada card aqui usa uma
/// capa GERADA: gradiente de cor sólida por seção + ícone temático.
/// Isso garante uma capa "moderna" e consistente sempre, sem depender
/// da qualidade variável do acervo do Archive.
class AudioNarrativeWidget extends StatelessWidget {
  const AudioNarrativeWidget({
    super.key,
    required this.sectionTitle,
    required this.items,
    required this.icon,
    required this.gradientColors,
    this.isLoading = false,
  });

  final String sectionTitle;
  final List<MediaItem> items;
  final IconData icon;
  final List<Color> gradientColors;
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
            height: _cardSize + 40,
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
                        child: _NarrativeCard(
                          item: items[index],
                          icon: icon,
                          gradientColors: gradientColors,
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

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({
    required this.item,
    required this.icon,
    required this.gradientColors,
  });

  final MediaItem item;
  final IconData icon;
  final List<Color> gradientColors;

  void _play() {
    final fallbackTrack = item.toTrackIfFallback();
    if (fallbackTrack == null) return; // item mal formado: não toca nada
    appProviderContainer
        .read(playerNotifierProvider.notifier)
        .playTrack(fallbackTrack);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _play,
      child: SizedBox(
        width: AudioNarrativeWidget._cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(
                    height: AudioNarrativeWidget._cardSize,
                    width: AudioNarrativeWidget._cardSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradientColors,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 48,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
                  // Gradiente escuro embaixo pra legibilidade do
                  // título, igual aos cards de gênero do Spotify.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.75),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

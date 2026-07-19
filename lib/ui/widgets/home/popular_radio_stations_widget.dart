import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/riverpod/app_provider_container.dart';
import '../../../core/audio/player_notifier.dart';
import '../../../features/search/data/track_media_item_mapper.dart';
import '../image_widget.dart';

/// "Estações de Rádio Popular": carrossel horizontal de cards quadrados
/// (estilo "rádio de gênero" do Spotify), populado só com faixas mais
/// tocadas do Jamendo (HomeScreenController.loadPopularRadioStations).
///
/// IMPORTANTE sobre o toque no card: estes MediaItems vêm marcados com
/// `extras['isFallbackSource'] == true` (ver track_media_item_mapper.dart).
/// Eles NÃO têm um videoId do YouTube, então NÃO podem ir pelo
/// `PlayerController.playPlayListSong` legado (que tentaria resolver
/// stream por videoId e falharia silenciosamente). O tap aqui replica
/// exatamente o padrão já usado em list_widget.dart: reconstrói o Track
/// original via `toTrackIfFallback()` e toca via `playerNotifierProvider`
/// (Riverpod), que resolve a URL certa através do PlaybackResolver.
class PopularRadioStationsWidget extends StatelessWidget {
  const PopularRadioStationsWidget({
    super.key,
    required this.stations,
    this.isLoading = false,
  });

  final List<MediaItem> stations;
  final bool isLoading;

  static const double _cardSize = 120;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && stations.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 12),
            child: Text(
              "popularRadioStations".tr,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          SizedBox(
            height: _cardSize + 40,
            child: isLoading && stations.isEmpty
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
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: 12,
                          left: index == 0 ? 0 : 0,
                        ),
                        child: _RadioCard(station: station),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.station});
  final MediaItem station;

  void _play() {
    final fallbackTrack = station.toTrackIfFallback();
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
        width: PopularRadioStationsWidget._cardSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  ImageWidget(song: station, size: PopularRadioStationsWidget._cardSize),
                  // Gradiente escuro embaixo pra legibilidade do título,
                  // igual aos cards "Chill Rock"/"Disney Hits" do Spotify.
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
                      station.title,
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

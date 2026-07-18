import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';

import '../../../core/audio/player_notifier.dart';

/// Mini player flutuante das faixas "fallback" (Internet Archive:
/// Minutos de Reflexão/Contos da Noite/Poesia Sonora, e Jamendo:
/// Estações de Rádio Popular) — tocadas via [playerNotifierProvider]
/// (Riverpod), fora do pipeline antigo do GetX/AudioHandler.
///
/// IMPORTANTE: antes desta correção, este widget existia mas nunca era
/// montado em NENHUMA tela — então tocar essas faixas não tinha
/// nenhum feedback visual (nem controles, nem erro), dando a
/// impressão de "não funciona ao tocar". Agora ele é montado direto
/// na Home (ver home_screen.dart) e some sozinho quando não há faixa
/// tocando.
class PlayerWidget extends ConsumerWidget {
  const PlayerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerNotifierProvider);
    final track = state.currentTrack;

    // Mostra qualquer erro de reprodução (ex.: faixa que falhou ao
    // resolver a URL) — antes disso era engolido em silêncio, sem
    // nenhuma tela escutando o provider.
    ref.listen(playerNotifierProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        Get.snackbar(
          'Erro ao reproduzir',
          next.errorMessage!,
          isDismissible: true,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    });

    if (track == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: track.artworkUrl.isNotEmpty
                  ? Image.network(
                      track.artworkUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackCover(),
                    )
                  : _fallbackCover(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (state.isBuffering)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              IconButton(
                icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
                onPressed: () =>
                    ref.read(playerNotifierProvider.notifier).togglePlayPause(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFF3A3A3A),
      child: const Icon(Icons.music_note, color: Colors.white70, size: 22),
    );
  }
}

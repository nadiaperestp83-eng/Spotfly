import 'package:audio_service/audio_service.dart';

import '../../../core/models/track.dart';

/// Converte um Track genérico (Piped/Jamendo) num MediaItem, pro item
/// aparecer nas listas de "Songs" da UI antiga junto com os resultados
/// do YouTube.
///
/// IMPORTANTE: isso resolve só a EXIBIÇÃO na lista. A reprodução real
/// desses itens (tocar a faixa) ainda depende do pipeline de player
/// atual, que hoje só sabe resolver stream por videoId do YouTube. Os
/// `extras` abaixo guardam sourceId/sourceTrackId pra permitir, num
/// próximo passo, que o PlayerController use o PlaybackResolver
/// (lib/core/playback/playback_resolver.dart) quando detectar
/// `isFallbackSource: true`. Isso NÃO faz parte desta migração de
/// busca/home — é só o "gancho" deixado pronto.
extension TrackMediaItemMapper on Track {
  MediaItem toFallbackMediaItem() {
    return MediaItem(
      id: '${sourceId}_$sourceTrackId',
      title: title,
      artist: artist,
      duration: duration,
      artUri: artworkUrl.isNotEmpty ? Uri.tryParse(artworkUrl) : null,
      extras: {
        'isFallbackSource': true,
        'fallbackSourceId': sourceId,
        'fallbackSourceTrackId': sourceTrackId,
        'url': null,
      },
    );
  }
}

/// Caminho inverso do mapper acima: reconstrói o Track original a partir
/// de um MediaItem "fallback" (Piped/Jamendo) — é o "gancho" que o
/// comentário da extension acima menciona. Usado nos pontos da UI onde o
/// toque em "play" precisa decidir se o item vai pelo pipeline legado
/// (AudioHandler/videoId, itens reais do YouTube) ou pelo PlayerNotifier
/// + PlaybackResolver (itens de fallback).
extension FallbackMediaItemToTrackMapper on MediaItem {
  /// Devolve o Track original se este MediaItem foi criado por
  /// [TrackMediaItemMapper.toFallbackMediaItem]. Devolve `null` se for um
  /// item real do YouTube (sem `isFallbackSource: true` nos extras) —
  /// nesse caso a reprodução deve continuar pelo pipeline legado.
  Track? toTrackIfFallback() {
    if (extras?['isFallbackSource'] != true) return null;
    final fallbackSourceId = extras!['fallbackSourceId'] as String?;
    final fallbackSourceTrackId = extras!['fallbackSourceTrackId'] as String?;
    if (fallbackSourceId == null || fallbackSourceTrackId == null) {
      return null;
    }
    return Track(
      id: id,
      title: title,
      artist: artist ?? '',
      artworkUrl: artUri?.toString() ?? '',
      duration: duration,
      sourceId: fallbackSourceId,
      sourceTrackId: fallbackSourceTrackId,
    );
  }
}

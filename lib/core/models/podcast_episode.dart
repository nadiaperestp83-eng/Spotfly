import 'package:meta/meta.dart';

import 'track.dart';

/// Modelo unificado devolvido pelo AudioContentService
/// (lib/features/search/data/sources/audio_content_service.dart),
/// independente da fonte original (iTunes ou Internet Archive). É isso
/// que permite ao HomeScreenController continuar consumindo UM único
/// tipo de dado pras 3 seções narrativas da Home, sem precisar saber
/// de onde cada episódio veio.
@immutable
class PodcastEpisode {
  final String id;
  final String title;
  final String? description;
  final String artist; // nome do podcast/programa (ou "Domínio Público")
  final String audioUrl; // link direto do arquivo de áudio (mp3)
  final String artworkUrl;
  final Duration? duration;
  final String sourceId; // 'itunes' | 'internetarchive'

  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.artist,
    required this.audioUrl,
    required this.sourceId,
    this.description,
    this.artworkUrl = '',
    this.duration,
  });

  /// Converte pro Track genérico já usado pelo resto do app
  /// (PlaybackResolver + TrackMediaItemMapper.toFallbackMediaItem()) —
  /// mesmo pipeline que Internet Archive/Piped/Jamendo já usam pra
  /// tocar e aparecer na UI. sourceId aqui precisa bater com a chave
  /// registrada em playbackResolverProvider (ver
  /// core/providers/providers.dart), senão o player não sabe resolver
  /// a URL na hora de tocar.
  Track toTrack() => Track(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: duration,
        sourceId: sourceId,
        sourceTrackId: audioUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'artist': artist,
        'audioUrl': audioUrl,
        'artworkUrl': artworkUrl,
        'durationSeconds': duration?.inSeconds,
        'sourceId': sourceId,
      };

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) => PodcastEpisode(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        artist: json['artist'] as String,
        audioUrl: json['audioUrl'] as String,
        artworkUrl: json['artworkUrl'] as String? ?? '',
        duration: json['durationSeconds'] != null
            ? Duration(seconds: json['durationSeconds'] as int)
            : null,
        sourceId: json['sourceId'] as String,
      );
}

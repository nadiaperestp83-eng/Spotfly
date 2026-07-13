import 'package:meta/meta.dart';

@immutable
class Track {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration? duration;

  // --- Metadados privados de origem ---
  // Nunca lidos pela UI. Só o PlaybackResolver e o SearchCoordinator
  // têm motivo legítimo para acessar isso.
  final String sourceId; // ex: 'youtube', 'jamendo', 'piped'
  final String sourceTrackId; // id interno na fonte
  final int? bitrateKbps; // usado só para ranking no coordinator

  // --- Enriquecimento (preenchido pelo MetadataService, opcional) ---
  // Também é metadado invisível à UI de origem — a UI só lê
  // title/artist/artworkUrl normalmente, sem saber que foram "limpos".
  final bool isEnriched;
  final List<String> relatedTitles; // faixas parecidas (Last.fm), uso futuro

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.sourceId,
    required this.sourceTrackId,
    this.duration,
    this.bitrateKbps,
    this.isEnriched = false,
    this.relatedTitles = const [],
  });

  Track copyWith({
    String? title,
    String? artist,
    String? artworkUrl,
    int? bitrateKbps,
    bool? isEnriched,
    List<String>? relatedTitles,
  }) =>
      Track(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        duration: duration,
        sourceId: sourceId,
        sourceTrackId: sourceTrackId,
        bitrateKbps: bitrateKbps ?? this.bitrateKbps,
        isEnriched: isEnriched ?? this.isEnriched,
        relatedTitles: relatedTitles ?? this.relatedTitles,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

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
  final String sourceId;       // ex: 'youtube', 'jamendo'
  final String sourceTrackId;  // id interno na fonte
  final int? bitrateKbps;      // usado só para ranking no coordinator

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.sourceId,
    required this.sourceTrackId,
    this.duration,
    this.bitrateKbps,
  });

  Track copyWith({int? bitrateKbps}) => Track(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: duration,
        sourceId: sourceId,
        sourceTrackId: sourceTrackId,
        bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      );
}

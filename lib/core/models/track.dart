import 'package:meta/meta.dart';

@immutable
class Track {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final Duration? duration;

  final String sourceId;
  final String sourceTrackId;
  final int? bitrateKbps;

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

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

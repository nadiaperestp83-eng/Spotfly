import 'package:meta/meta.dart';

import '../../../core/models/track.dart';

@immutable
class QueueState {
  final List<Track> tracks;
  final int currentIndex;

  const QueueState({this.tracks = const [], this.currentIndex = -1});

  Track? get current =>
      (currentIndex >= 0 && currentIndex < tracks.length)
          ? tracks[currentIndex]
          : null;

  bool get hasNext => currentIndex + 1 < tracks.length;
  bool get hasPrevious => currentIndex - 1 >= 0;

  QueueState copyWith({List<Track>? tracks, int? currentIndex}) {
    return QueueState(
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

import 'package:meta/meta.dart';

import '../models/track.dart';

@immutable
class PlayerState {
  final Track? currentTrack;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration? duration;
  final String? errorMessage;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration,
    this.errorMessage,
  });

  PlayerState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    String? errorMessage,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: errorMessage,
    );
  }
}

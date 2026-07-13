import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/player_notifier.dart';
import '../../../core/models/track.dart';
import 'queue_state.dart';

class QueueNotifier extends Notifier<QueueState> {
  @override
  QueueState build() => const QueueState();

  void setQueueAndPlay(List<Track> tracks, {int startIndex = 0}) {
    state = QueueState(tracks: tracks, currentIndex: startIndex);
    _playCurrent();
  }

  void addToQueue(Track track) {
    state = state.copyWith(tracks: [...state.tracks, track]);
  }

  void next() {
    if (!state.hasNext) return;
    state = state.copyWith(currentIndex: state.currentIndex + 1);
    _playCurrent();
  }

  void previous() {
    if (!state.hasPrevious) return;
    state = state.copyWith(currentIndex: state.currentIndex - 1);
    _playCurrent();
  }

  void _playCurrent() {
    final track = state.current;
    if (track != null) {
      ref.read(playerNotifierProvider.notifier).playTrack(track);
    }
  }
}

final queueNotifierProvider =
    NotifierProvider<QueueNotifier, QueueState>(QueueNotifier.new);

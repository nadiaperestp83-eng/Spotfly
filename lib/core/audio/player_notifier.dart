import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/providers.dart';
import 'i_audio_player_service.dart';
import 'player_state.dart';

class PlayerNotifier extends Notifier<PlayerState> {
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;

  IAudioPlayerService get _audioService => ref.read(audioPlayerServiceProvider);

  @override
  PlayerState build() {
    final audioService = ref.watch(audioPlayerServiceProvider);

    _positionSub = audioService.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _durationSub = audioService.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = audioService.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing, isBuffering: false);
    });

    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
    });

    return const PlayerState();
  }

  Future<void> playTrack(Track track) async {
    state = state.copyWith(
      currentTrack: track,
      isBuffering: true,
      errorMessage: null,
    );
    try {
      final resolver = ref.read(playbackResolverProvider);
      final url = await resolver.resolve(track);
      await _audioService.play(url);
    } catch (e) {
      state = state.copyWith(
        isBuffering: false,
        errorMessage: 'Não foi possível reproduzir esta faixa.',
      );
    }
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.resume();
    }
  }

  Future<void> seek(Duration position) => _audioService.seek(position);

  Future<void> setVolume(double volume) => _audioService.setVolume(volume);
}

final playerNotifierProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);

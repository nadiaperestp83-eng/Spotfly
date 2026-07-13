import 'dart:async';
import 'package:riverpod/riverpod.dart';
import '../models/track.dart';
import '../playback/i_playback_resolver.dart';
import 'i_audio_player_service.dart';
import 'player_state.dart';

class PlayerNotifier extends Notifier<PlayerState> {
  late final IAudioPlayerService _audioService;
  late final IPlaybackResolver _resolver;
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _durationSub;

  @override
  PlayerState build() {
    _audioService = ref.watch(audioPlayerServiceProvider);
    _resolver = ref.watch(playbackResolverProvider);

    _positionSub = _audioService.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _durationSub = _audioService.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });
    _playingSub = _audioService.playingStream.listen((playing) {
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
    state = state.copyWith(currentTrack: track, isBuffering: true);
    final url = await _resolver.resolve(track); // Player não sabe de onde veio
    await _audioService.play(url);
  }

  Future<void> togglePlayPause() async {
    state.isPlaying ? await _audioService.pause() : await _audioService.resume();
  }

  Future<void> seek(Duration position) => _audioService.seek(position);
}

final playerNotifierProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);

// Declarados aqui só para o exemplo compilar isolado —
// a definição real vive em core/providers/providers.dart
late final audioPlayerServiceProvider =
    Provider<IAudioPlayerService>((ref) => throw UnimplementedError());
late final playbackResolverProvider =
    Provider<IPlaybackResolver>((ref) => throw UnimplementedError());

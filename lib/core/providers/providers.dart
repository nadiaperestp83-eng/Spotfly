import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/search/data/i_music_source.dart';
import '../../features/search/data/sources/jamendo_source.dart';
import '../../features/search/data/sources/piped_source.dart';
import '../../features/search/data/sources/youtube_music_source.dart';
import '../../features/search/domain/search_coordinator.dart';
import '../audio/i_audio_player_service.dart';
import '../audio/just_audio_player_service.dart';
import '../metadata/i_metadata_provider.dart';
import '../metadata/lastfm_metadata_service.dart';
import '../playback/i_playback_resolver.dart';
import '../playback/playback_resolver.dart';

final audioPlayerServiceProvider = Provider<IAudioPlayerService>((ref) {
  final service = JustAudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

/// Lista de fontes usada pelo SearchCoordinator (Orquestrador) para o
/// fallback automático e sequencial. A ORDEM É A PRIORIDADE:
/// 1º YoutubeMusicSource (YT interno) -> 2º PipedSource -> 3º JamendoSource.
/// Pra trocar a prioridade, reordenar a lista abaixo — nada mais muda
/// (UI e notifiers não sabem que essa ordem existe).
final musicSourcesProvider = Provider<List<IMusicSource>>((ref) {
  return [
    YoutubeMusicSource(),
    PipedSource(),
    JamendoSource(
      clientId: const String.fromEnvironment('JAMENDO_CLIENT_ID'),
    ),
  ];
});

final playbackResolverProvider = Provider<IPlaybackResolver>((ref) {
  return PlaybackResolver(ref.watch(musicSourcesProvider));
});

final metadataProviderProvider = Provider<IMetadataProvider>((ref) {
  return LastFmMetadataService(
    apiKey: const String.fromEnvironment('LASTFM_API_KEY'),
  );
});

final searchCoordinatorProvider = Provider<SearchCoordinator>((ref) {
  return SearchCoordinator(
    ref.watch(musicSourcesProvider),
    metadataProvider: ref.watch(metadataProviderProvider),
  );
});

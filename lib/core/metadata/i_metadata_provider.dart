import '../models/track.dart';
import 'scrobble_payload.dart';

/// Enriquece uma Track bruta (vinda de qualquer IMusicSource) com
/// metadados "limpos": título correto, capa em alta qualidade, faixas
/// parecidas. SearchCoordinator conhece só esta interface — nunca
/// LastFmMetadataService diretamente.
abstract class IMetadataProvider {
  /// Chamado para TODA faixa retornada na busca (em paralelo, com timeout).
  /// Deve ser leve: título limpo, artista correto, capa em alta qualidade.
  Future<Track> enrich(Track track);

  /// Faixas parecidas. Deliberadamente separado de enrich() — é mais
  /// pesado (2ª chamada à API) e não deve rodar para toda a lista de
  /// busca. Uso pontual: tela de detalhe da faixa, fila "tocar a seguir".
  Future<List<String>> findSimilar(Track track, {int limit = 5});

  ScrobblePayload prepareScrobble(Track track, {required DateTime playedAt});
}

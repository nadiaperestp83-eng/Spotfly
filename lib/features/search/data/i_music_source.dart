import '../../../core/models/home_section.dart';
import '../../../core/models/track.dart';

abstract class IMusicSource {
  String get sourceId;

  Future<List<Track>> search(String query);

  /// Seções de conteúdo para a Home (ex: "Populares", "Quick picks").
  /// Deve lançar exceção em caso de falha real (rede/API),
  /// e retornar lista vazia apenas quando a fonte legitimamente
  /// não tem conteúdo — o SearchCoordinator usa essa diferença
  /// para decidir entre "tentar próxima fonte" e "propagar erro".
  Future<List<HomeSection>> getHomeSections();

  Future<String> resolveStreamUrl(Track track);
}

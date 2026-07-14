import 'package:meta/meta.dart';

import 'track.dart';

/// Contrato de retorno unificado de qualquer IMusicSource/SearchCoordinator.
///
/// [categories] preserva o formato "cru" que a UI antiga já espera:
/// chaves como 'Songs', 'Videos', 'Albums', 'Artists',
/// 'Featured playlists', 'Community playlists' e 'searchEndpoint'.
/// A fonte "youtube" (YtMusicApiSource) popula isso rico, com todas as
/// categorias. Fontes de fallback (Piped/Jamendo) só populam 'Songs'
/// (categoria simulada a partir da lista simples de faixas).
///
/// [continuationParams] guarda, por categoria/aba, os parâmetros
/// necessários pra buscar a próxima página (equivalente ao antigo
/// `additionalParamNext[tabName]`). Só a fonte "youtube" preenche isso;
/// Piped/Jamendo não suportam paginação.
///
/// [allTracks] é a lista simples (sem categorias) — usada internamente
/// pelo Orquestrador pra enriquecimento de metadados e por qualquer
/// consumidor futuro que só precise de uma lista plana de Track.
///
/// [sourceId] identifica quem respondeu ('youtube' | 'piped' | 'jamendo'
/// | 'none'). A UI nunca precisa decidir com base nisso, mas o
/// Coordinator usa pra rotear continuações pra fonte certa.
@immutable
class SearchResult {
  final Map<String, dynamic> categories;
  final Map<String, Map<String, dynamic>> continuationParams;
  final List<Track> allTracks;
  final String sourceId;

  const SearchResult({
    this.categories = const {},
    this.continuationParams = const {},
    this.allTracks = const [],
    required this.sourceId,
  });

  bool get isEmpty => categories.isEmpty && allTracks.isEmpty;
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

/// Busca e mantém uma lista de proxies HTTP públicos e gratuitos
/// (ProxyScrape + Geonode), pra tentar contornar bloqueio de rate-limit
/// do YouTube sem depender de um proxy fixo configurado manualmente.
///
/// Baseado no ProxyManager real do Musify (gokadzev/Musify), simplificado:
/// eles usam 4 fontes (ProxyScrape, Geonode, spys.me, open proxy list) com
/// agrupamento por país e pool de recursos reutilizáveis; aqui ficou só
/// com as 2 fontes que têm formato JSON/texto simples de parsear (as
/// outras duas exigem regex específico pro formato de cada site, mais
/// frágil de manter). O restante do comportamento segue o mesmo espírito:
/// blocklist com TTL (não descarta um proxy pra sempre, só por um tempo),
/// e sempre cai pro modo direto se nenhum proxy responder.
class FreeProxyService {
  FreeProxyService._();

  static const String _proxyScrapeUrl =
      'https://api.proxyscrape.com/v2/?request=getproxies&protocol=http&timeout=4000&country=all&ssl=all&anonymity=all';

  static const String _geonodeUrl =
      'https://proxylist.geonode.com/api/proxy-list?limit=50&page=1&sort_by=lastChecked&sort_type=desc&protocols=http';

  static const String _cacheKey = 'freeProxyList';
  static const String _cacheFetchedAtKey = 'freeProxyListFetchedAt';

  /// Não busca a lista de novo antes desse intervalo — evita bater nas
  /// APIs a cada música tocada (mesma ideia do
  /// `_proxyRefreshIntervalMinutes` do Musify, só que mais curto porque
  /// aqui não há um pool de proxies "já validados" pra usar entretanto).
  static const Duration _refreshInterval = Duration(hours: 1);

  static const Duration _fetchTimeout = Duration(seconds: 6);

  /// Proxy que falhou fica de fora por esse tempo, não pra sempre —
  /// mesma ideia do `_blockedProxyTtlMinutes` do Musify (lá é 30min).
  static const Duration _deadCooldown = Duration(minutes: 30);

  static List<String>? _memoryCache;
  static final Map<String, DateTime> _deadUntil = {};

  /// Devolve até [maxCandidates] endereços "ip:porta" pra tentar, na
  /// ordem, pulando os que estão em cooldown por falha recente.
  static Future<List<String>> getCandidates({int maxCandidates = 3}) async {
    final list = await _getList();
    if (list.isEmpty) return const [];
    _pruneExpiredCooldowns();
    return list
        .where((p) => !_deadUntil.containsKey(p))
        .take(maxCandidates)
        .toList();
  }

  /// Marca um proxy como falho por [_deadCooldown] — depois disso volta
  /// a ser candidato normalmente (proxies grátis vão e voltam).
  static void markDead(String proxyAddress) {
    _deadUntil[proxyAddress] = DateTime.now().add(_deadCooldown);
  }

  static void _pruneExpiredCooldowns() {
    final now = DateTime.now();
    _deadUntil.removeWhere((_, until) => now.isAfter(until));
  }

  static Future<List<String>> _getList() async {
    if (_memoryCache != null) return _memoryCache!;

    final appPrefs = Hive.isBoxOpen("AppPrefs")
        ? Hive.box("AppPrefs")
        : await Hive.openBox("AppPrefs");

    final cachedList = (appPrefs.get(_cacheKey) as List?)?.cast<String>();
    final fetchedAtMillis = appPrefs.get(_cacheFetchedAtKey) as int?;
    final isFresh = fetchedAtMillis != null &&
        DateTime.now().millisecondsSinceEpoch - fetchedAtMillis <
            _refreshInterval.inMilliseconds;

    if (cachedList != null && cachedList.isNotEmpty && isFresh) {
      _memoryCache = cachedList;
      return cachedList;
    }

    // As duas fontes são buscadas em paralelo e combinadas — se uma
    // falhar, a outra ainda pode salvar a tentativa.
    final results = await Future.wait([
      _fetchProxyScrape(),
      _fetchGeonode(),
    ]);
    final fresh = <String>{...results[0], ...results[1]}.toList();

    if (fresh.isEmpty) {
      // As duas fontes falharam agora: usa cache antigo (mesmo vencido)
      // se existir, em vez de ficar sem nenhum candidato.
      _memoryCache = cachedList ?? const [];
      return _memoryCache!;
    }

    await appPrefs.put(_cacheKey, fresh);
    await appPrefs.put(
        _cacheFetchedAtKey, DateTime.now().millisecondsSinceEpoch);
    _memoryCache = fresh;
    return fresh;
  }

  /// ProxyScrape: devolve texto simples, uma linha "ip:porta" por proxy.
  static Future<List<String>> _fetchProxyScrape() async {
    try {
      final response =
          await http.get(Uri.parse(_proxyScrapeUrl)).timeout(_fetchTimeout);
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return const [];
      }
      return const LineSplitter()
          .convert(response.body)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.contains(':'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Geonode: devolve JSON com uma lista de objetos {ip, port, ...}.
  static Future<List<String>> _fetchGeonode() async {
    try {
      final response =
          await http.get(Uri.parse(_geonodeUrl)).timeout(_fetchTimeout);
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      final data = (decoded is Map ? decoded['data'] : null) as List?;
      if (data == null) return const [];
      return data
          .whereType<Map>()
          .map((e) => '${e['ip']}:${e['port']}')
          .where((address) => !address.startsWith('null:') &&
              !address.endsWith(':null'))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

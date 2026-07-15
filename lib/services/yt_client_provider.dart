// lib/services/yt_client_provider.dart
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';
import '../models/settings_model.dart';

class YtClientProvider {
  static YtClientProvider? _instance;
  final SettingsModel settings;

  YtClientProvider._(this.settings);

  static YtClientProvider getInstance(SettingsModel settings) {
    _instance ??= YtClientProvider._(settings);
    return _instance!;
  }

  // Atualiza as configurações em tempo real
  void updateSettings(SettingsModel newSettings) {
    // Como settings é passado por referência, podemos apenas atualizar
    // ou recriar o cliente. Melhor: manter um cliente atualizável.
  }

  /// Cria um [http.Client] configurado com proxy (se habilitado)
  http.Client createClient() {
    if (!settings.useProxy || settings.proxyHost.isEmpty) {
      return http.Client();
    }

    final ioClient = HttpClient()
      ..findProxy = (uri) {
        // Retorna a string no formato "PROXY host:port"
        return 'PROXY ${settings.proxyHost}:${settings.proxyPort}';
      }
      ..badCertificateCallback = (cert, host, port) => true; // ignore certificados se necessário

    return IOClient(ioClient);
  }
}

/// Configuração estática do proxy embutido no app.
/// O usuário NÃO define isso pela UI — é fixo no build.
class ProxyConfig {
  /// Endereço no formato "host:porta". Ex: "123.45.67.89:8080"
  static const String proxyAddress = "SEU_PROXY_HOST:PORTA";

  /// Timeout usado nas tentativas via proxy (menor, para falhar rápido
  /// e cair no fallback direto sem travar a UI).
  static const Duration proxyTimeout = Duration(seconds: 8);

  /// Timeout usado na tentativa direta (fallback).
  static const Duration directTimeout = Duration(seconds: 12);
}

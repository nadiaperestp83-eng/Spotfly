/// Configuração estática do proxy embutido no app.
/// O usuário NÃO define isso pela UI — é fixo no build.
class ProxyConfig {
  /// Endereço no formato "host:porta". Ex: "123.45.67.89:8080"
  ///
  /// ⚠️ Enquanto isso continuar com o valor placeholder abaixo, o app
  /// NÃO tenta usar proxy nenhum — ele vai direto para a conexão
  /// direta, sem desperdiçar tempo tentando resolver um host inválido.
  /// Troque pelo endereço real do seu proxy quando tiver um.
  static const String proxyAddress = "SEU_PROXY_HOST:PORTA";

  /// Timeout usado nas tentativas via proxy (menor, para falhar rápido
  /// e cair no fallback direto sem travar a UI).
  static const Duration proxyTimeout = Duration(seconds: 8);

  /// Timeout usado na tentativa direta (fallback). Quando NÃO há proxy
  /// configurado (caso comum), esta é a ÚNICA tentativa de rede — por
  /// isso é mais generosa: getManifest() faz várias requisições
  /// internas (player JS, decifragem de assinatura, etc.) que podem
  /// legitimamente passar de 10s numa conexão móvel mais lenta.
  static const Duration directTimeout = Duration(seconds: 20);

  /// true somente se [proxyAddress] foi de fato preenchido com um
  /// endereço real (não vazio e diferente do placeholder). Usado por
  /// YtClientProvider e por quem faz o fallback proxy->direto para
  /// pular completamente a tentativa de proxy quando não há um
  /// configurado — evita perder segundos tentando resolver um host
  /// que não existe antes de cair pra conexão direta.
  static bool get isConfigured =>
      proxyAddress.trim().isNotEmpty &&
      proxyAddress.trim() != "SEU_PROXY_HOST:PORTA";
}

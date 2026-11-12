class ApiSettings {
  const ApiSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  String get chatCompletionsUrl {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return normalized.endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';
  }
}

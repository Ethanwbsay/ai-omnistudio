enum ImageTaskMode {
  textToImage('文生图'),
  imageToImage('图生图'),
  edit('图片编辑');

  const ImageTaskMode(this.label);
  final String label;
}

class ImageApiProfile {
  const ImageApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.generationPath = 'images/generations',
    this.editPath = 'images/edits',
    this.responseFormat = '',
    this.generationTimeoutMinutes = 15,
    this.responseMode = 'auto',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String generationPath;
  final String editPath;
  final String responseFormat;
  final int generationTimeoutMinutes;
  final String responseMode;

  bool get usesStreaming =>
      responseMode == 'stream' ||
      (responseMode == 'auto' &&
          Uri.tryParse(baseUrl.trim())?.host == 'suoxie.codes' &&
          (model.trim().startsWith('gpt-image-') ||
              model.trim().startsWith('chatgpt-image-')));

  Uri endpoint(ImageTaskMode mode) {
    final base = Uri.parse(baseUrl.trim());
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('API Base URL 无效');
    }
    final path =
        (mode == ImageTaskMode.textToImage ? generationPath : editPath).trim();
    if (path.isEmpty ||
        path.contains('://') ||
        path.contains('?') ||
        path.contains('#')) {
      throw const FormatException('请求路径无效');
    }
    // This provider exposes Images only under /v1. Normalize its bare website
    // URL while preserving custom prefixes and explicitly versioned paths.
    final prefix = base.host == 'suoxie.codes' &&
            (base.path.isEmpty || base.path == '/') &&
            path.replaceAll(RegExp(r'^/+'), '').startsWith('images/')
        ? '/v1'
        : base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/${path.replaceAll(RegExp(r'^/+'), '')}');
  }

  bool get isComplete {
    try {
      endpoint(ImageTaskMode.textToImage);
      endpoint(ImageTaskMode.edit);
      return name.trim().isNotEmpty &&
          apiKey.trim().isNotEmpty &&
          model.trim().isNotEmpty &&
          generationTimeoutMinutes >= 1 &&
          generationTimeoutMinutes <= 30 &&
          ['', 'b64_json', 'url'].contains(responseFormat) &&
          ['auto', 'json', 'stream'].contains(responseMode);
    } on FormatException {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'generationPath': generationPath,
        'editPath': editPath,
        'responseFormat': responseFormat,
        'generationTimeoutMinutes': generationTimeoutMinutes,
        'responseMode': responseMode,
      };

  factory ImageApiProfile.fromJson(Map<String, dynamic> json) =>
      ImageApiProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
        model: json['model'] as String,
        generationPath:
            json['generationPath'] as String? ?? 'images/generations',
        editPath: json['editPath'] as String? ?? 'images/edits',
        responseFormat: json['responseFormat'] as String? ?? '',
        generationTimeoutMinutes:
            (json['generationTimeoutMinutes'] as num?)?.toInt() ?? 15,
        responseMode: json['responseMode'] as String? ?? 'auto',
      );
}

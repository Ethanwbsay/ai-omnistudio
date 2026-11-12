enum VideoProvider {
  ark('火山方舟 · Seedance'),
  grok('xAI · Grok Imagine');

  const VideoProvider(this.label);
  final String label;

  String get baseUrl => this == ark
      ? 'https://ark.cn-beijing.volces.com/api/v3'
      : 'https://api.x.ai/v1';
  String get model =>
      this == ark ? 'doubao-seedance-2-5-260628' : 'grok-imagine-video';
  String get submitPath =>
      this == ark ? 'contents/generations/tasks' : 'videos/generations';
  String get queryPath =>
      this == ark ? 'contents/generations/tasks/{id}' : 'videos/{id}';
}

class VideoApiProfile {
  const VideoApiProfile(
      {required this.id,
      required this.name,
      required this.provider,
      required this.baseUrl,
      required this.apiKey,
      required this.model,
      required this.submitPath,
      required this.queryPath});

  final String id, name, baseUrl, apiKey, model, submitPath, queryPath;
  final VideoProvider provider;

  // This site's NextChat proxy routes video queries by model and client ID.
  // Keep the extension scoped to its verified endpoint, not native xAI APIs.
  bool get usesPaiaiProxy {
    final uri = Uri.tryParse(baseUrl.trim());
    return provider == VideoProvider.grok &&
        uri?.host == 'chat.yueyued.top' &&
        uri!.path.replaceAll(RegExp(r'/+$'), '') == '/api/openai/v1';
  }

  String get proxyClientId => 'ai-tavern-$id';

  int get minDuration => provider == VideoProvider.ark ? 4 : 1;
  int get maxDuration =>
      provider == VideoProvider.ark && model.contains('2-5') ? 30 : 15;
  List<String> get resolutions => model == 'grok-imagine-video' ||
          (provider == VideoProvider.ark &&
              (model.contains('-fast-') || model.contains('-mini-')))
      ? ['480p', '720p']
      : ['480p', '720p', '1080p'];

  Uri endpoint({String? taskId, String? taskModel}) {
    final base = Uri.parse(baseUrl.trim());
    final path = (taskId == null ? submitPath : queryPath).trim();
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty ||
        path.isEmpty ||
        path.contains('://') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains('..') ||
        path.contains('\\') ||
        (taskId != null && !path.contains('{id}'))) {
      throw const FormatException('视频 API 地址或相对请求路径无效');
    }
    // Encode the ID as a single segment, including slashes returned by a gateway.
    final suffix = taskId == null
        ? path
        : path.replaceAll('{id}', Uri.encodeComponent(taskId));
    final uri = Uri.parse(
        '${base.toString().replaceAll(RegExp(r'/+$'), '')}/${suffix.replaceAll(RegExp(r'^/+'), '')}');
    return usesPaiaiProxy && taskId != null
        ? uri.replace(queryParameters: {'grok_model': taskModel ?? model})
        : uri;
  }

  bool get isComplete {
    try {
      endpoint();
      endpoint(taskId: 'validation');
      return [name, apiKey, model].every((e) => e.trim().isNotEmpty);
    } on FormatException {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'submitPath': submitPath,
        'queryPath': queryPath
      };

  factory VideoApiProfile.fromJson(Map<String, dynamic> j) => VideoApiProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      provider: VideoProvider.values.byName(j['provider'] as String),
      baseUrl: j['baseUrl'] as String,
      apiKey: j['apiKey'] as String,
      model: j['model'] as String,
      submitPath: j['submitPath'] as String,
      queryPath: j['queryPath'] as String);
}

class VideoOptions {
  const VideoOptions(
      {this.duration = 5,
      this.ratio = '16:9',
      this.resolution = '720p',
      this.audio});
  final int duration;
  final String ratio, resolution;
  final bool? audio;

  static List<String> ratios(VideoProvider provider) =>
      provider == VideoProvider.ark
          ? ['16:9', '9:16', '1:1', '4:3', '3:4', '21:9', 'adaptive']
          : ['16:9', '9:16', '1:1', '4:3', '3:4', '3:2', '2:3'];

  Map<String, dynamic> request(
      VideoApiProfile profile, String prompt, String? image) {
    final ark = profile.provider == VideoProvider.ark;
    if (prompt.trim().isEmpty ||
        !profile.isComplete ||
        duration < profile.minDuration ||
        duration > profile.maxDuration ||
        !ratios(profile.provider).contains(ratio) ||
        !profile.resolutions.contains(resolution)) {
      throw const FormatException('请检查视频配置、提示词、时长和分辨率。');
    }
    return {
      'model': profile.model.trim(),
      if (ark)
        'content': [
          {'type': 'text', 'text': prompt.trim()},
          if (image != null)
            {
              'type': 'image_url',
              'image_url': {'url': image},
              'role': 'first_frame'
            },
        ]
      else ...{
        'prompt': prompt.trim(),
        if (image != null) 'image': {'url': image},
      },
      'duration': duration,
      // Seedance 2.5 requires adaptive ratio for first-frame generation.
      if (ark)
        'ratio': image != null ? 'adaptive' : ratio
      else
        'aspect_ratio': ratio,
      'resolution': resolution,
      if (audio != null) 'generate_audio': audio,
    };
  }
}

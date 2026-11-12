import 'video_api_profile.dart';

class VideoJob {
  const VideoJob(
      {required this.id,
      required this.profileId,
      required this.provider,
      required this.baseUrl,
      required this.queryPath,
      required this.taskId,
      required this.prompt,
      required this.model,
      required this.mode,
      required this.createdAt,
      required this.duration,
      required this.ratio,
      required this.resolution,
      this.status = 'pending',
      this.remoteUrl = '',
      this.localPath = '',
      this.error = '',
      this.proxyClientId = ''});

  final String id, profileId, baseUrl, queryPath, taskId, prompt, model, mode;
  final String status, remoteUrl, localPath, error, ratio, resolution;
  final VideoProvider provider;
  final String proxyClientId;
  final DateTime createdAt;
  final int duration;
  bool get terminal => ['failed', 'expired', 'cancelled'].contains(status);
  bool get canResume => taskId.isNotEmpty && !terminal && localPath.isEmpty;
  String get statusLabel => switch (status) {
        'queued' => '排队中',
        'running' || 'pending' => '生成中',
        'succeeded' || 'done' => localPath.isEmpty ? '待下载' : '已保存',
        'failed' => '生成失败',
        'expired' => '任务已过期',
        'cancelled' => '服务端已取消',
        _ => '待查询',
      };

  VideoJob copyWith(
          {String? status,
          String? remoteUrl,
          String? localPath,
          String? error}) =>
      VideoJob(
          id: id,
          profileId: profileId,
          provider: provider,
          baseUrl: baseUrl,
          queryPath: queryPath,
          taskId: taskId,
          prompt: prompt,
          model: model,
          mode: mode,
          createdAt: createdAt,
          duration: duration,
          ratio: ratio,
          resolution: resolution,
          status: status ?? this.status,
          remoteUrl: remoteUrl ?? this.remoteUrl,
          localPath: localPath ?? this.localPath,
          error: error ?? this.error,
          proxyClientId: proxyClientId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'provider': provider.name,
        'baseUrl': baseUrl,
        'queryPath': queryPath,
        'taskId': taskId,
        'prompt': prompt,
        'model': model,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
        'duration': duration,
        'ratio': ratio,
        'resolution': resolution,
        'status': status,
        'remoteUrl': remoteUrl,
        'localPath': localPath,
        'error': error,
        'proxyClientId': proxyClientId,
      };

  factory VideoJob.fromJson(Map<String, dynamic> j) => VideoJob(
      id: j['id'] as String,
      profileId: j['profileId'] as String,
      provider: VideoProvider.values.byName(j['provider'] as String),
      baseUrl: j['baseUrl'] as String,
      queryPath: j['queryPath'] as String,
      taskId: j['taskId'] as String,
      prompt: j['prompt'] as String,
      model: j['model'] as String,
      mode: j['mode'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      duration: j['duration'] as int,
      ratio: j['ratio'] as String,
      resolution: j['resolution'] as String,
      status: j['status'] as String,
      remoteUrl: j['remoteUrl'] as String? ?? '',
      localPath: j['localPath'] as String? ?? '',
      error: j['error'] as String? ?? '',
      proxyClientId: j['proxyClientId'] as String? ?? '');
}

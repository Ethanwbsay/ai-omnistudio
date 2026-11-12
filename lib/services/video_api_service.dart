import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../models/video_api_profile.dart';

class VideoApiException implements Exception {
  const VideoApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VideoTaskResult {
  const VideoTaskResult(this.status, {this.url = '', this.error = ''});
  final String status, url, error;
  bool get complete => status == 'succeeded' || status == 'done';
  bool get terminal => ['failed', 'expired', 'cancelled'].contains(status);
}

class VideoApiService {
  VideoApiService(
      {http.Client Function()? clientFactory,
      this.requestTimeout = const Duration(seconds: 60),
      this.downloadTimeout = const Duration(minutes: 10),
      this.maxDownloadBytes = 300 * 1024 * 1024})
      : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout, downloadTimeout;
  final int maxDownloadBytes;
  http.Client? _active;
  Completer<void>? _stop;

  void cancel() {
    if (_stop != null && !_stop!.isCompleted) _stop!.complete();
    _active?.close();
  }

  void dispose() => cancel();

  Future<T> _run<T>(Future<T> Function(http.Client, Completer<void>) action,
      Duration timeout) async {
    if (_active != null) throw const VideoApiException('已有视频请求正在进行。');
    final client = _clientFactory();
    final stop = Completer<void>();
    _active = client;
    _stop = stop;
    try {
      return await Future.any<T>([
        action(client, stop).timeout(timeout),
        stop.future
            .then<T>((_) => throw const VideoApiException('已暂停查询，可在任务中继续。')),
      ]);
    } on VideoApiException {
      rethrow;
    } on TimeoutException {
      throw const VideoApiException(
          '视频请求超时。已提交的任务可继续查询；提交超时请先检查服务商控制台，避免重复计费。');
    } catch (_) {
      throw const VideoApiException('视频请求未完成，请检查网络和 API 配置。');
    } finally {
      if (!stop.isCompleted) stop.complete();
      client.close();
      _active = null;
      _stop = null;
    }
  }

  Future<Map<String, dynamic>> _json(
      http.Client client, VideoApiProfile profile,
      {Map<String, dynamic>? body,
      String? taskId,
      String? taskModel,
      String? proxyClientId}) async {
    final request = http.Request(body == null ? 'GET' : 'POST',
        profile.endpoint(taskId: taskId, taskModel: taskModel))
      ..headers['Authorization'] = 'Bearer ${profile.apiKey.trim()}'
      ..headers['Accept'] = 'application/json';
    if (profile.usesPaiaiProxy) {
      final clientId = proxyClientId ?? profile.proxyClientId;
      if (clientId.isNotEmpty) request.headers['x-paiai-client-id'] = clientId;
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await client.send(request));
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw VideoApiException('视频接口返回无效 JSON（HTTP ${response.statusCode}）。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VideoApiException(
          '视频 API 错误（HTTP ${response.statusCode}）：${_error(data)}');
    }
    return data;
  }

  static String _error(Map<String, dynamic> data) {
    final error = data['error'];
    return (error is Map ? error['message'] ?? error['code'] : error)
            ?.toString() ??
        data['message']?.toString() ??
        '请检查模型权限、余额或请求参数。';
  }

  Future<String> submit(
      {required VideoApiProfile profile,
      required String prompt,
      required VideoOptions options,
      String? image}) async {
    final body = options.request(profile, prompt, image);
    return _run((client, stop) async {
      final data = await _json(client, profile, body: body);
      final id =
          data[profile.provider == VideoProvider.ark ? 'id' : 'request_id'];
      if (id is! String || id.isEmpty) {
        throw const VideoApiException('接口未返回任务 ID，请检查服务商控制台。');
      }
      return id;
    }, requestTimeout);
  }

  Future<VideoTaskResult> query(VideoApiProfile profile, String taskId,
          {String? taskModel, String? proxyClientId}) =>
      _run((client, stop) async {
        final data = await _json(client, profile,
            taskId: taskId, taskModel: taskModel, proxyClientId: proxyClientId);
        var status = data['status'];
        if (profile.usesPaiaiProxy) {
          final nested = data['data'];
          status ??= data['state'] ?? (nested is Map ? nested['status'] : null);
          status = switch (status?.toString().toLowerCase()) {
            'completed' || 'succeeded' || 'success' || 'ready' => 'done',
            'queued' || 'running' || 'processing' => 'pending',
            'error' || 'cancelled' || 'canceled' => 'failed',
            final value => value,
          };
        }
        final allowed = profile.provider == VideoProvider.ark
            ? [
                'queued',
                'running',
                'succeeded',
                'failed',
                'cancelled',
                'expired'
              ]
            : ['pending', 'done', 'failed', 'expired'];
        final content =
            data[profile.provider == VideoProvider.ark ? 'content' : 'video'];
        var url = content is Map
            ? content[
                profile.provider == VideoProvider.ark ? 'video_url' : 'url']
            : null;
        if (profile.usesPaiaiProxy) {
          url = _proxyVideoUrl(data);
          // The website accepts a completed video URL even without status.
          if (url is String &&
              url.isNotEmpty &&
              !['failed', 'expired'].contains(status)) {
            status = 'done';
          }
        }
        if (status is! String || !allowed.contains(status)) {
          throw const VideoApiException('接口返回未知任务状态。');
        }
        if (content is Map && content['respect_moderation'] == false) {
          return const VideoTaskResult('failed', error: '视频未通过服务商内容审核。');
        }
        final result = VideoTaskResult(status,
            url: url is String ? url : '',
            error: ['failed', 'expired', 'cancelled'].contains(status)
                ? _error(data)
                : '');
        if (result.complete && result.url.isEmpty) {
          throw const VideoApiException('任务成功但未返回视频地址。');
        }
        return result;
      }, requestTimeout);

  static String _proxyVideoUrl(dynamic data, [int depth = 0]) {
    if (depth > 6) return '';
    if (data is List) {
      for (final item in data) {
        final url = _proxyVideoUrl(item, depth + 1);
        if (url.isNotEmpty) return url;
      }
    } else if (data is Map) {
      for (final key in [
        'video_url',
        'videoUrl',
        'output_url',
        'result_url',
        'url'
      ]) {
        final value = data[key];
        if (value is String &&
            RegExp(r'^(https?://|/?(?:api/openai/)?(?:v1/)?(?:videos|media/videos)/)',
                    caseSensitive: false)
                .hasMatch(value.trim())) {
          return value.trim();
        }
      }
      for (final key in ['data', 'output', 'result', 'video', 'videos']) {
        final url = _proxyVideoUrl(data[key], depth + 1);
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }

  static Uri _mediaUri(String url, VideoApiProfile? profile, String? model) {
    var uri = Uri.parse(url);
    if (profile?.usesPaiaiProxy != true) return uri;
    final base = Uri.parse(profile!.baseUrl.replaceAll(RegExp(r'/+$'), ''));
    final proxyPath = base.path;
    final rawPath = uri.path.replaceFirst(RegExp(r'^/'), '');
    final nativeMedia =
        RegExp(r'^v1/(?:videos/[^/]+(?:/content)?|media/videos/[^/]+)$')
            .hasMatch(rawPath);
    if (!uri.hasScheme || nativeMedia) {
      if (uri.hasAuthority && !nativeMedia) {
        throw const VideoApiException('视频地址无效。');
      }
      final path = uri.path.startsWith('$proxyPath/')
          ? uri.path
          : '$proxyPath/${rawPath.replaceFirst(RegExp(r'^v1/'), '')}';
      uri = base.replace(path: path, query: uri.hasQuery ? uri.query : null);
    }
    if (uri.origin == base.origin && uri.path.startsWith('$proxyPath/')) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'grok_model': model ?? profile.model
      });
    }
    return uri;
  }

  Future<void> download(String url, File destination,
      {VideoApiProfile? profile,
      String? taskModel,
      String? proxyClientId}) async {
    final uri = _mediaUri(url, profile, taskModel);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const VideoApiException('接口返回无效的视频下载地址。');
    }
    final partial = File('${destination.path}.part');
    Future<void>? downloadWork;
    try {
      await _run<void>((client, stop) {
        downloadWork = _download(
            client, stop, uri, partial, destination, profile, proxyClientId);
        return downloadWork!;
      }, downloadTimeout);
    } finally {
      // Wait for the stream and file sink to close before another resume can
      // reuse this task's partial file, including on cancellation or timeout.
      if (downloadWork != null) {
        try {
          await downloadWork;
        } catch (_) {}
      }
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _download(
      http.Client client,
      Completer<void> stop,
      Uri uri,
      File partial,
      File destination,
      VideoApiProfile? profile,
      String? proxyClientId) async {
    Future<T> interruptible<T>(Future<T> work) => Future.any<T>([
          work,
          stop.future.then<T>((_) => throw const VideoApiException('下载已暂停。')),
        ]);
    http.StreamedResponse? response;
    var target = uri;
    // Proxy media needs authentication; restrict it to the verified origin and
    // API prefix. Follow redirects manually so external CDN requests get no Key.
    for (var hop = 0; hop <= 5; hop++) {
      final request = http.Request('GET', target)..followRedirects = false;
      if (profile?.usesPaiaiProxy == true) {
        final api = Uri.parse(profile!.baseUrl.replaceAll(RegExp(r'/+$'), ''));
        if (target.origin == api.origin &&
            target.path.startsWith('${api.path}/')) {
          request.headers['Authorization'] = 'Bearer ${profile.apiKey.trim()}';
          final clientId = proxyClientId ?? profile.proxyClientId;
          if (clientId.isNotEmpty) {
            request.headers['x-paiai-client-id'] = clientId;
          }
        }
      }
      final current =
          await interruptible<http.StreamedResponse>(client.send(request));
      response = current;
      if (![301, 302, 303, 307, 308].contains(current.statusCode)) break;
      final location = current.headers['location'];
      await interruptible(current.stream.drain<void>().timeout(requestTimeout));
      if (location == null || hop == 5) {
        throw const VideoApiException('视频下载重定向失败。');
      }
      target = target.resolve(location);
      if (!['http', 'https'].contains(target.scheme) ||
          target.userInfo.isNotEmpty) {
        throw const VideoApiException('视频重定向地址无效。');
      }
    }
    final media = response!;
    if (media.statusCode != 200) {
      throw VideoApiException('视频下载失败（HTTP ${media.statusCode}），可继续查询刷新地址。');
    }
    if ((media.contentLength ?? 0) > maxDownloadBytes) {
      throw const VideoApiException('视频超过本地下载大小限制（300 MB）。');
    }
    final sink = partial.openWrite();
    final chunks = StreamIterator(media.stream.timeout(requestTimeout));
    var total = 0;
    final header = <int>[];
    try {
      while (await interruptible(chunks.moveNext())) {
        final chunk = chunks.current;
        if (stop.isCompleted) throw const VideoApiException('下载已暂停。');
        total += chunk.length;
        if (total > maxDownloadBytes) {
          throw const VideoApiException('视频超过本地下载大小限制（300 MB）。');
        }
        if (header.length < 12) {
          header.addAll(chunk.take(12 - header.length));
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await chunks.cancel();
      await sink.close();
    }
    if (stop.isCompleted) throw const VideoApiException('下载已暂停。');
    if (header.length < 12 ||
        ascii.decode(header.sublist(4, 8), allowInvalid: true) != 'ftyp') {
      throw const VideoApiException('下载内容不是有效的 MP4 视频。');
    }
    await partial.rename(destination.path);
  }
}

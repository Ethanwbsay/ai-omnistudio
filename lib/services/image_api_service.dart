import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/image_api_profile.dart';
import '../models/image_reference_limits.dart';
import 'image_response_reader.dart';

class ImageApiException implements Exception {
  const ImageApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImageApiResult {
  const ImageApiResult(this.bytes, {this.revisedPrompt = ''});
  final Uint8List bytes;
  final String revisedPrompt;
}

enum ImageRequestStage {
  generating('正在上传参考图并等待模型生成…'),
  receiving('服务端已响应，正在接收图片结果…'),
  downloading('图片已生成，正在下载结果…'),
  saving('正在保存图片…');

  const ImageRequestStage(this.label);
  final String label;
}

class ImageDownloadSource {
  const ImageDownloadSource({this.bytes, this.url, this.revisedPrompt = ''});
  final Uint8List? bytes;
  final Uri? url;
  final String revisedPrompt;
}

// Keep completed images and remaining URLs when downloading fails. Retrying
// these sources performs only GET requests, never a new paid generation POST.
class ImageDownloadException extends ImageApiException {
  const ImageDownloadException(super.message,
      {required this.completed, required this.pending});
  final List<ImageApiResult> completed;
  final List<ImageDownloadSource> pending;
}

class ImageApiService {
  ImageApiService(
      {http.Client Function()? clientFactory,
      this.timeout,
      this.downloadTimeout = const Duration(minutes: 3)})
      : _clientFactory = clientFactory ?? (() => http.Client());

  final http.Client Function() _clientFactory;
  final Duration? timeout;
  final Duration downloadTimeout;
  http.Client? _active;
  Completer<void>? _cancelSignal;

  void cancel() {
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _active?.close();
  }

  void dispose() => cancel();

  Future<List<ImageApiResult>> generate(
      {required ImageApiProfile profile,
      required ImageTaskMode mode,
      required String prompt,
      String size = '',
      String quality = '',
      int count = 1,
      List<Uint8List> images = const [],
      Uint8List? mask,
      void Function(ImageRequestStage)? onProgress}) async {
    if (_active != null) throw const ImageApiException('已有图片请求正在进行。');
    if (!profile.isComplete ||
        prompt.trim().isEmpty ||
        count < 1 ||
        count > 10) {
      throw const ImageApiException('请检查图片 API 配置、提示词和生成数量。');
    }
    if (mode != ImageTaskMode.textToImage && images.isEmpty) {
      throw const ImageApiException('请先选择参考图片。');
    }
    final references = mode == ImageTaskMode.textToImage
        ? const <Uint8List>[]
        : List<Uint8List>.of(images);
    if (references.length > ImageReferenceLimits.maxCount ||
        references.any((image) =>
            image.isEmpty ||
            image.length > ImageReferenceLimits.maxImageBytes) ||
        references.fold<int>(0, (total, image) => total + image.length) >
            ImageReferenceLimits.maxTotalBytes) {
      throw const ImageApiException('最多上传 16 张参考图，单张不超过 50 MB，总大小不超过 100 MB。');
    }
    return _run((client, signal) => _execute(client, profile, mode, prompt,
        size, quality, count, references, mask, signal, onProgress));
  }

  Future<List<ImageApiResult>> retryDownloads(List<ImageDownloadSource> sources,
          {void Function(ImageRequestStage)? onProgress}) =>
      _run((client, signal) =>
          _downloadSources(client, signal, sources, onProgress));

  Future<List<ImageApiResult>> _run(
      Future<List<ImageApiResult>> Function(http.Client, Completer<void>)
          action) async {
    if (_active != null) throw const ImageApiException('已有图片请求正在进行。');
    final client = _clientFactory();
    _active = client;
    final signal = Completer<void>();
    _cancelSignal = signal;
    try {
      return await Future.any([
        action(client, signal),
        signal.future.then<List<ImageApiResult>>(
            (_) => throw const ImageApiException('已停止生成。')),
      ]);
    } on ImageApiException {
      rethrow;
    } catch (e) {
      throw ImageApiException(
          signal.isCompleted ? '已停止生成。' : '图片请求处理失败（${e.runtimeType}）。');
    } finally {
      if (!signal.isCompleted) signal.complete();
      client.close();
      _active = null;
      _cancelSignal = null;
    }
  }

  Future<List<ImageApiResult>> _execute(
      http.Client client,
      ImageApiProfile profile,
      ImageTaskMode mode,
      String prompt,
      String size,
      String quality,
      int count,
      List<Uint8List> images,
      Uint8List? mask,
      Completer<void> signal,
      void Function(ImageRequestStage)? onProgress) async {
    final fields = <String, dynamic>{
      'model': profile.model.trim(),
      'prompt': prompt.trim(),
      'n': count,
      if (profile.usesStreaming) 'stream': true,
      if (profile.usesStreaming) 'partial_images': 1,
      if (size.isNotEmpty) 'size': size,
      if (quality.isNotEmpty) 'quality': quality,
      if (profile.responseFormat.isNotEmpty)
        'response_format': profile.responseFormat,
    };
    final endpoint = profile.endpoint(mode);
    final http.BaseRequest request;
    if (mode == ImageTaskMode.textToImage) {
      request = http.Request('POST', endpoint)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(fields);
    } else {
      final multipart = http.MultipartRequest('POST', endpoint)
        ..fields.addAll(
            fields.map((key, value) => MapEntry(key, value.toString())));
      // Keep the single-image field compatible with existing providers. For
      // multiple images use the array field documented by the Images API.
      for (var index = 0; index < images.length; index++) {
        multipart.files.add(http.MultipartFile.fromBytes(
            images.length == 1 ? 'image' : 'image[]', images[index],
            filename: images.length == 1
                ? 'reference.png'
                : 'reference-${index + 1}.png',
            contentType: MediaType('image', 'png')));
      }
      if (mode == ImageTaskMode.edit && mask != null) {
        multipart.files.add(http.MultipartFile.fromBytes('mask', mask,
            filename: 'mask.png', contentType: MediaType('image', 'png')));
      }
      request = multipart;
    }
    request.headers['Authorization'] = 'Bearer ${profile.apiKey.trim()}';
    request.headers['Accept'] = profile.usesStreaming
        ? 'text/event-stream, application/json'
        : 'application/json';
    // Avoid proxy compression/streaming incompatibilities for large Base64 JSON.
    request.headers['Accept-Encoding'] = 'identity';
    final wait = timeout ?? Duration(minutes: profile.generationTimeoutMinutes);
    onProgress?.call(ImageRequestStage.generating);
    http.Response response;
    String? requestId;
    int? statusCode;
    var receivedBytes = 0;
    var headersReceived = false;
    final elapsed = Stopwatch()..start();
    try {
      response = await (() async {
        final streamed = await client.send(request);
        _checkCancelled(signal);
        requestId =
            streamed.headers['x-request-id'] ?? streamed.headers['request-id'];
        statusCode = streamed.statusCode;
        headersReceived = true;
        onProgress?.call(ImageRequestStage.receiving);
        return readImageResponse(streamed,
            expectedCount: count, onBytes: (count) => receivedBytes = count);
      })()
          .timeout(wait);
    } on TimeoutException {
      throw ImageApiException(
          '生成接口等待超时（最长 ${profile.generationTimeoutMinutes} 分钟）'
          '${_requestReference(requestId, profile.apiKey)}。服务端可能仍在处理或已经扣费，请先检查服务商记录，避免重复生成。'
          '可在图片 API 配置中调整生成等待时间。');
    } on ImageStreamException catch (e) {
      throw ImageApiException(
          '图片流式响应未完成${_requestReference(requestId, profile.apiKey)}：'
          '${e.message.replaceAll(profile.apiKey.trim(), '[已隐藏]').replaceAll(RegExp(r'https?://\S+'), '[地址已隐藏]')}。'
          '不会自动重新生成，请核对服务商记录。');
    } catch (e) {
      _checkCancelled(signal);
      final phase = headersReceived ? '接收图片结果时连接中断' : '等待服务端响应时连接中断';
      final detail = e is http.ClientException ? e.message : e.toString();
      // Preserve the useful transport reason, but never show keys, signed URLs
      // or a gateway's copy of the submitted request in the diagnostic text.
      final safe = detail
          .replaceAll(profile.apiKey.trim(), '[已隐藏]')
          .replaceAll(RegExp(r'https?://\S+'), '[地址已隐藏]')
          .replaceAll(RegExp(r'[\r\n]'), ' ');
      throw ImageApiException(
          '$phase（${e.runtimeType}，${elapsed.elapsed.inSeconds} 秒'
          '${statusCode == null ? '' : '，HTTP $statusCode'}，已接收 $receivedBytes 字节）'
          '${_requestReference(requestId, profile.apiKey)}。'
          '${safe.length > 180 ? safe.substring(0, 180) : safe}。'
          '服务端可能已经生成并扣费，请先核对服务商记录，不要直接重复生成。');
    }
    _checkCancelled(signal);
    if (response.statusCode == 408 ||
        response.statusCode == 504 ||
        response.statusCode == 524) {
      throw ImageApiException('服务商网关超时（HTTP ${response.statusCode}）'
          '${_requestReference(requestId, profile.apiKey)}。服务端可能已经扣费，请先检查服务商记录；延长应用等待时间无法恢复网关已中断的请求。');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ImageApiException('接口返回内容无法识别（HTTP ${response.statusCode}）'
          '${_requestReference(requestId, profile.apiKey)}。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body is Map ? body['error'] : null;
      final detail = error is Map ? error['message'] : error;
      // Some gateways include the submitted payload in their error message.
      final message =
          detail?.toString().replaceAll(profile.apiKey.trim(), '[已隐藏]');
      throw ImageApiException(
          '图片接口失败（HTTP ${response.statusCode}）${message == null ? '' : '：$message'}');
    }
    final data = body is Map ? body['data'] : null;
    if (data is! List || data.isEmpty) {
      throw const ImageApiException('接口未返回图片，请确认模型支持 Images API。');
    }
    final sources = <ImageDownloadSource>[];
    for (final item in data) {
      _checkCancelled(signal);
      if (item is! Map) throw const ImageApiException('图片返回格式无效。');
      Uint8List? bytes;
      Uri? downloadUrl;
      final encoded = item['b64_json'];
      final url = item['url'];
      if (encoded is String && encoded.isNotEmpty) {
        try {
          bytes = base64Decode(encoded);
        } catch (_) {
          throw const ImageApiException('接口返回的 Base64 图片无效。');
        }
      } else if (url is String && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (url.startsWith('data:image/')) {
          try {
            bytes = UriData.parse(url).contentAsBytes();
          } catch (_) {
            throw const ImageApiException('接口返回的内嵌图片无效。');
          }
        } else if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw const ImageApiException('接口返回的图片地址无效。');
        } else {
          downloadUrl = uri;
        }
      } else {
        throw const ImageApiException('接口未返回 b64_json 或图片 URL。');
      }
      _checkCancelled(signal);
      if (bytes != null && bytes.isEmpty) {
        throw const ImageApiException('接口返回了空图片。');
      }
      sources.add(ImageDownloadSource(
          bytes: bytes,
          url: downloadUrl,
          revisedPrompt: item['revised_prompt']?.toString() ?? ''));
    }
    return _downloadSources(client, signal, sources, onProgress);
  }

  Future<List<ImageApiResult>> _downloadSources(
      http.Client client,
      Completer<void> signal,
      List<ImageDownloadSource> sources,
      void Function(ImageRequestStage)? onProgress) async {
    final results = <ImageApiResult>[];
    for (var index = 0; index < sources.length; index++) {
      _checkCancelled(signal);
      final source = sources[index];
      var bytes = source.bytes;
      if (bytes == null) {
        final uri = source.url;
        if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw const ImageApiException('接口返回的图片地址无效。');
        }
        onProgress?.call(ImageRequestStage.downloading);
        try {
          // Never forward the API credential to a returned image URL.
          final downloaded = await client.get(uri).timeout(downloadTimeout);
          _checkCancelled(signal);
          if (downloaded.statusCode != 200) {
            throw ImageApiException(
                '生成成功，但图片下载失败（HTTP ${downloaded.statusCode}）。');
          }
          bytes = downloaded.bodyBytes;
          if (bytes.isEmpty) throw const ImageApiException('生成成功，但下载的图片为空。');
        } catch (e) {
          _checkCancelled(signal);
          final detail = e is TimeoutException
              ? '生成成功，但图片下载超时。'
              : e is ImageApiException
                  ? e.message
                  : '生成成功，但图片下载中断，请检查网络。';
          throw ImageDownloadException('$detail 可重试下载，无需重新调用模型。',
              completed: List.unmodifiable(results),
              pending: List.unmodifiable(sources.sublist(index)));
        }
      }
      _checkCancelled(signal);
      results.add(ImageApiResult(bytes, revisedPrompt: source.revisedPrompt));
    }
    return results;
  }

  String _requestReference(String? id, String apiKey) {
    if (id == null || id.isEmpty) return '';
    final sanitized =
        id.replaceAll(apiKey.trim(), '[已隐藏]').replaceAll(RegExp(r'[\r\n]'), '');
    return '，请求 ID：${sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized}';
  }

  void _checkCancelled(Completer<void> signal) {
    if (signal.isCompleted) throw const ImageApiException('已停止生成。');
  }
}

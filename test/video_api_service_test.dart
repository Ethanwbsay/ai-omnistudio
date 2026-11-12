import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:question_solver/models/video_api_profile.dart';
import 'package:question_solver/services/video_api_service.dart';

VideoApiProfile profile(VideoProvider provider, {String? model}) =>
    VideoApiProfile(
        id: provider.name,
        name: provider.label,
        provider: provider,
        baseUrl: provider.baseUrl,
        apiKey: 'test-secret',
        model: model ?? provider.model,
        submitPath: provider.submitPath,
        queryPath: provider.queryPath);

final mp4Header = [
  0,
  0,
  0,
  24,
  ...ascii.encode('ftyp'),
  ...ascii.encode('isom'),
  0,
  0,
  0,
  0
];

void main() {
  test(
      'Seedance sends official content schema, 30s and adaptive first-frame ratio',
      () async {
    final requests = <http.Request>[];
    final service = VideoApiService(
        clientFactory: () => MockClient((r) async {
              requests.add(r);
              return http.Response('{"id":"ark-task"}', 200);
            }));
    expect(
        await service.submit(
            profile: profile(VideoProvider.ark),
            prompt: '你好',
            options: const VideoOptions(duration: 30, audio: true),
            image: 'data:image/png;base64,AA=='),
        'ark-task');
    final request = requests.single;
    expect(request.url.toString(),
        'https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks');
    expect(request.headers['Authorization'], 'Bearer test-secret');
    final body = jsonDecode(request.body);
    expect(body['model'], 'doubao-seedance-2-5-260628');
    expect(body['content'], [
      {'type': 'text', 'text': '你好'},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,AA=='},
        'role': 'first_frame'
      }
    ]);
    expect(body['ratio'], 'adaptive');
    expect(body['duration'], 30);
    expect(body['generate_audio'], true);
    expect(body.containsKey('prompt'), false);
  });

  test('Grok uses prompt/image and request_id; model defaults omit audio',
      () async {
    late Map<String, dynamic> body;
    final service = VideoApiService(
        clientFactory: () => MockClient((r) async {
              expect(r.url.path, '/v1/videos/generations');
              body = jsonDecode(r.body) as Map<String, dynamic>;
              return http.Response('{"request_id":"grok-task"}', 200);
            }));
    expect(
        await service.submit(
            profile: profile(VideoProvider.grok),
            prompt: 'cat walking',
            options: const VideoOptions(duration: 15, ratio: '9:16'),
            image: 'data:image/png;base64,AA=='),
        'grok-task');
    expect(body['image'], {'url': 'data:image/png;base64,AA=='});
    expect(body['aspect_ratio'], '9:16');
    expect(body['prompt'], 'cat walking');
    expect(body.containsKey('generate_audio'), false);
    expect(body.containsKey('content'), false);
  });

  test('supported model parameter ranges are validated before sending', () {
    expect(
        () => const VideoOptions(duration: 31)
            .request(profile(VideoProvider.ark), 'x', null),
        throwsFormatException);
    expect(
        () => const VideoOptions(duration: 3)
            .request(profile(VideoProvider.ark), 'x', null),
        throwsFormatException);
    expect(
        () => const VideoOptions(duration: 16)
            .request(profile(VideoProvider.grok), 'x', null),
        throwsFormatException);
    expect(
        () => const VideoOptions(resolution: '1080p')
            .request(profile(VideoProvider.grok), 'x', null),
        throwsFormatException);
    expect(
        const VideoOptions(resolution: '1080p').request(
            profile(VideoProvider.grok, model: 'grok-imagine-video-1.5'),
            'x',
            null)['resolution'],
        '1080p');
  });

  for (final provider in VideoProvider.values) {
    test('${provider.name} parses pending, success and failure states',
        () async {
      final responses = provider == VideoProvider.ark
          ? [
              {'status': 'queued'},
              {'status': 'running'},
              {
                'status': 'succeeded',
                'content': {'video_url': 'https://cdn.example/video.mp4'}
              },
              {
                'status': 'failed',
                'error': {'message': 'out of quota'}
              },
              {'status': 'cancelled'},
            ]
          : [
              {'status': 'pending'},
              {
                'status': 'done',
                'video': {
                  'url': 'https://cdn.example/video.mp4',
                  'respect_moderation': true
                }
              },
              {
                'status': 'failed',
                'error': {'message': 'out of quota'}
              },
              {'status': 'expired'},
            ];
      final service = VideoApiService(
          clientFactory: () => MockClient((r) async {
                expect(r.method, 'GET');
                expect(r.url.pathSegments.last, 'task/with slash');
                return http.Response(jsonEncode(responses.removeAt(0)), 200);
              }));
      final results = <VideoTaskResult>[];
      while (responses.isNotEmpty) {
        results.add(await service.query(profile(provider), 'task/with slash'));
      }
      expect(results.first.complete, false);
      expect(results.where((r) => r.complete).single.url,
          'https://cdn.example/video.mp4');
      expect(results.where((r) => r.error == 'out of quota').single.terminal,
          true);
      expect(results.last.terminal, true);
    });
  }

  test('unknown states and missing video URLs fail without silently completing',
      () async {
    for (final response in [
      '{"status":"unknown"}',
      '{"status":"done"}',
      '{"status":"done","video":{"url":"x","respect_moderation":false}}'
    ]) {
      final service = VideoApiService(
          clientFactory: () =>
              MockClient((_) async => http.Response(response, 200)));
      if (response.contains('respect_moderation')) {
        expect((await service.query(profile(VideoProvider.grok), 'id')).status,
            'failed');
      } else {
        await expectLater(service.query(profile(VideoProvider.grok), 'id'),
            throwsA(isA<VideoApiException>()));
      }
    }
  });

  test('API errors and non-JSON are reported; submissions are never retried',
      () async {
    for (final response in [
      http.Response('{"error":{"message":"invalid key"}}', 401),
      http.Response('<html>bad gateway</html>', 502)
    ]) {
      var calls = 0;
      final service = VideoApiService(
          clientFactory: () => MockClient((_) async {
                calls++;
                return response;
              }));
      await expectLater(
          service.submit(
              profile: profile(VideoProvider.grok),
              prompt: 'x',
              options: const VideoOptions()),
          throwsA(isA<VideoApiException>().having((e) => e.message,
              'HTTP status', contains('HTTP ${response.statusCode}'))));
      expect(calls, 1);
    }
  });

  test('download is streamed to disk without credentials and rejects HTML',
      () async {
    final dir = await Directory.systemTemp.createTemp('video-download-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.mp4');
    final service = VideoApiService(
        clientFactory: () => MockClient.streaming((r, _) async {
              expect(r.headers.containsKey('Authorization'), false);
              return http.StreamedResponse(
                  Stream.fromIterable([
                    mp4Header.take(5).toList(),
                    mp4Header.skip(5).toList(),
                    [1, 2, 3]
                  ]),
                  200);
            }));
    await service.download('https://cdn.example/video.mp4', file);
    expect(await file.readAsBytes(), [...mp4Header, 1, 2, 3]);
    expect(await File('${file.path}.part').exists(), false);
    final bad = VideoApiService(
        clientFactory: () => MockClient(
            (_) async => http.Response('<html>not a video</html>', 200)));
    await expectLater(
        bad.download('https://cdn.example/bad', File('${dir.path}/bad.mp4')),
        throwsA(isA<VideoApiException>()));
    expect(await File('${dir.path}/bad.mp4').exists(), false);
    expect(await File('${dir.path}/bad.mp4.part').exists(), false);
  });

  test('download size is bounded even without Content-Length', () async {
    final dir = await Directory.systemTemp.createTemp('video-size-');
    addTearDown(() => dir.delete(recursive: true));
    final service = VideoApiService(
        maxDownloadBytes: 12,
        clientFactory: () => MockClient.streaming((_, body) async =>
            http.StreamedResponse(Stream.value(mp4Header), 200)));
    final file = File('${dir.path}/large.mp4');
    await expectLater(service.download('https://cdn.example/v', file),
        throwsA(isA<VideoApiException>()));
    expect(await file.exists(), false);
    expect(await File('${file.path}.part').exists(), false);
  });

  test(
      'pause interrupts a stalled media stream and closes partial file before retry',
      () async {
    final dir = await Directory.systemTemp.createTemp('video-pause-');
    addTearDown(() => dir.delete(recursive: true));
    final stream = StreamController<List<int>>();
    final started = Completer<void>();
    final service = VideoApiService(
        clientFactory: () => MockClient.streaming((_, body) async {
              started.complete();
              return http.StreamedResponse(stream.stream, 200);
            }));
    final file = File('${dir.path}/pause.mp4');
    final download = service.download('https://cdn.example/v', file);
    final check = expectLater(download, throwsA(isA<VideoApiException>()));
    await started.future;
    stream.add(mp4Header);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.cancel();
    await check.timeout(const Duration(seconds: 2));
    expect(await file.exists(), false);
    expect(await File('${file.path}.part').exists(), false);
    await stream.close();
  });
}

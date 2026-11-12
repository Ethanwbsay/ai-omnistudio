import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:question_solver/models/image_api_profile.dart';
import 'package:question_solver/services/image_api_service.dart';

const imageProfile = ImageApiProfile(
    id: 'image-api',
    name: '测试图片 API',
    baseUrl: 'https://example.test/v1/',
    apiKey: 'test-secret',
    model: 'image-model');

http.Response imageResponse() => http.Response(
    jsonEncode({
      'data': [
        {
          'b64_json': base64Encode([1, 2, 3]),
          'revised_prompt': 'revised'
        },
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

class ImageStreamingClient extends http.BaseClient {
  ImageStreamingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

class LocalImageHttpOverrides extends HttpOverrides {}

void main() {
  test(
      'gateway whitespace heartbeats and complete JSON finish before stream EOF',
      () async {
    final body = StreamController<List<int>>();
    final api = ImageApiService(
        timeout: const Duration(seconds: 1),
        clientFactory: () => ImageStreamingClient(
            (_) async => http.StreamedResponse(body.stream, 200)));
    final result = api.generate(
        profile: imageProfile,
        mode: ImageTaskMode.imageToImage,
        prompt: 'test',
        images: [
          Uint8List.fromList([1])
        ]);
    body.add(utf8.encode(' \n \n'));
    final json = jsonEncode({
      'data': [
        {
          'b64_json': base64Encode([1, 2, 3])
        }
      ],
      'revised_prompt': 'quoted brace \\" } [中文'
    });
    final encoded = utf8.encode(json);
    for (var index = 0; index < encoded.length; index += 7) {
      body.add(encoded.sublist(index, (index + 7).clamp(0, encoded.length)));
    }
    expect((await result).single.bytes, [1, 2, 3]);
    await body.close();
  });

  test(
      'real HTTP transport recovers full image JSON with an incorrect body length',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final body = jsonEncode({
      'data': [
        {
          'b64_json': base64Encode([1, 2, 3])
        }
      ]
    });
    final sockets = <Socket>[];
    final listener = server.listen((socket) {
      sockets.add(socket);
      var replied = false;
      socket.listen((_) async {
        if (replied) return;
        replied = true;
        socket.add(ascii.encode(
            'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: ${body.length + 100}\r\nConnection: close\r\n\r\n$body'));
        await socket.flush();
        socket.destroy();
      });
    });
    final local = ImageApiProfile.fromJson({
      ...imageProfile.toJson(),
      'baseUrl': 'http://127.0.0.1:${server.port}/v1'
    });
    final api = ImageApiService(
        timeout: const Duration(seconds: 2),
        clientFactory: () =>
            IOClient(LocalImageHttpOverrides().createHttpClient(null)));
    try {
      expect(
          (await api.generate(
                  profile: local,
                  mode: ImageTaskMode.textToImage,
                  prompt: 'test'))
              .single
              .bytes,
          [1, 2, 3]);
    } finally {
      api.dispose();
      for (final socket in sockets) {
        socket.destroy();
      }
      await listener.cancel();
      await server.close();
    }
  });

  test(
      'truncated JSON reports the receiving phase, HTTP status and bytes without leaking keys',
      () async {
    final body = StreamController<List<int>>();
    final api = ImageApiService(
        clientFactory: () => ImageStreamingClient((_) async =>
            http.StreamedResponse(body.stream, 200,
                headers: {'x-request-id': 'rid-test'})));
    final result = api.generate(
        profile: imageProfile,
        mode: ImageTaskMode.imageToImage,
        prompt: 'test',
        images: [
          Uint8List.fromList([1])
        ]);
    final check = expectLater(
        result,
        throwsA(isA<ImageApiException>().having(
            (e) => e.message,
            'diagnostic',
            allOf(
                contains('接收图片结果时连接中断'),
                contains('HTTP 200'),
                contains('rid-test'),
                contains('Connection closed'),
                isNot(contains('test-secret')),
                isNot(contains('private=123'))))));
    body.add(utf8.encode('{"data":[{"b64_json":"unfinished'));
    body.addError(http.ClientException(
        'Connection closed test-secret https://cdn.test/a?private=123'));
    await check;
    await body.close();
  });

  test('failure before headers reports the waiting phase and never resubmits',
      () async {
    var calls = 0;
    final api = ImageApiService(
        clientFactory: () => ImageStreamingClient((_) async {
              calls++;
              throw http.ClientException('Connection reset by peer');
            }));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test'),
        throwsA(isA<ImageApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('等待服务端响应时连接中断'),
                contains('Connection reset by peer')))));
    expect(calls, 1);
  });

  test('gateway inline data URL images need no second HTTP request', () async {
    var calls = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((request) async {
              calls++;
              expect(request.headers['accept-encoding'], 'identity');
              return http.Response(
                  jsonEncode({
                    'data': [
                      {'url': 'data:image/png;base64,AQID'}
                    ]
                  }),
                  200);
            }));
    expect(
        (await api.generate(
                profile: imageProfile,
                mode: ImageTaskMode.textToImage,
                prompt: 'test'))
            .single
            .bytes,
        [1, 2, 3]);
    expect(calls, 1);
  });

  test('legacy profiles get longer waits and custom wait survives reopening',
      () {
    final legacy = {...imageProfile.toJson()}
      ..remove('generationTimeoutMinutes');
    expect(ImageApiProfile.fromJson(legacy).generationTimeoutMinutes, 15);
    final custom =
        ImageApiProfile.fromJson({...legacy, 'generationTimeoutMinutes': 30});
    expect(custom.isComplete, isTrue);
    expect(
        ImageApiProfile.fromJson(custom.toJson()).generationTimeoutMinutes, 30);
    for (final invalid in [0, 31]) {
      expect(
          ImageApiProfile.fromJson(
              {...legacy, 'generationTimeoutMinutes': invalid}).isComplete,
          isFalse);
    }
  });

  testWidgets('image-to-image can complete after the old five minute cutoff',
      (tester) async {
    var finished = false;
    final stages = <ImageRequestStage>[];
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async {
              await Future<void>.delayed(const Duration(minutes: 6));
              return imageResponse();
            }));
    final pending = api.generate(
        profile: imageProfile,
        mode: ImageTaskMode.imageToImage,
        prompt: 'change the sky',
        images: [
          Uint8List.fromList([1, 2, 3])
        ],
        onProgress: stages.add);
    pending.then((_) => finished = true);
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(finished, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect((await pending).single.bytes, [1, 2, 3]);
    expect(stages, [ImageRequestStage.generating, ImageRequestStage.receiving]);
  });

  test('download has its own budget after generation completes', () async {
    final stages = <ImageRequestStage>[];
    final api = ImageApiService(
        timeout: const Duration(milliseconds: 100),
        downloadTimeout: const Duration(seconds: 1),
        clientFactory: () => MockClient((request) async {
              if (request.method == 'POST') {
                return http.Response(
                    jsonEncode({
                      'data': [
                        {'url': 'https://cdn.test/output.png'}
                      ]
                    }),
                    200);
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
              return http.Response.bytes([1, 2, 3], 200);
            }));
    expect(
        await api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.imageToImage,
            prompt: 'test',
            images: [
              Uint8List.fromList([1])
            ],
            onProgress: stages.add),
        hasLength(1));
    expect(stages, contains(ImageRequestStage.downloading));
  });

  test(
      'download failure preserves partial images and retries only pending GETs',
      () async {
    var posts = 0, gets = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((request) async {
              if (request.method == 'POST') {
                posts++;
                return http.Response(
                    jsonEncode({
                      'data': [
                        {
                          'b64_json': base64Encode([1, 2, 3])
                        },
                        {
                          'url': 'https://cdn.test/output.png?signature=private'
                        },
                      ]
                    }),
                    200);
              }
              expect(request.headers.containsKey('authorization'), isFalse);
              return ++gets == 1
                  ? http.Response('unavailable', 503)
                  : http.Response.bytes([4, 5, 6], 200);
            }));
    late ImageDownloadException error;
    try {
      await api.generate(
          profile: imageProfile,
          mode: ImageTaskMode.textToImage,
          prompt: 'test');
      fail('expected a download failure');
    } on ImageDownloadException catch (e) {
      error = e;
    }
    expect(error.completed.single.bytes, [1, 2, 3]);
    expect(error.pending, hasLength(1));
    expect(error.message,
        allOf(contains('生成成功'), contains('503'), isNot(contains('private'))));
    expect((await api.retryDownloads(error.pending)).single.bytes, [4, 5, 6]);
    expect(posts, 1);
    expect(gets, 2);
  });

  test('download timeout retains a URL for retry and distinguishes generation',
      () async {
    final stalled = Completer<http.Response>();
    final api = ImageApiService(
        downloadTimeout: const Duration(milliseconds: 10),
        clientFactory: () =>
            MockClient((request) async => request.method == 'POST'
                ? http.Response(
                    jsonEncode({
                      'data': [
                        {'url': 'https://cdn.test/output.png'}
                      ]
                    }),
                    200)
                : await stalled.future));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test'),
        throwsA(isA<ImageDownloadException>()
            .having((e) => e.message, 'message', contains('图片下载超时'))
            .having((e) => e.pending.length, 'retry sources', 1)));
    stalled.complete(http.Response.bytes([1], 200));
  });

  test('incomplete response body times out with the request ID', () async {
    final body = StreamController<List<int>>();
    final stages = <ImageRequestStage>[];
    final api = ImageApiService(
        timeout: const Duration(milliseconds: 10),
        clientFactory: () => ImageStreamingClient((_) async =>
            http.StreamedResponse(body.stream, 200,
                headers: {'x-request-id': 'request-123'})));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test',
            onProgress: stages.add),
        throwsA(isA<ImageApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('生成接口等待超时'), contains('request-123'),
                contains('避免重复生成')))));
    expect(stages, contains(ImageRequestStage.receiving));
    await body.close();
  });

  test('HTML gateway timeout reports its HTTP status without resubmitting',
      () async {
    var requests = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async {
              requests++;
              return http.Response('<html>Gateway Timeout</html>', 504,
                  headers: {'x-request-id': 'gateway-1'});
            }));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test'),
        throwsA(isA<ImageApiException>().having(
            (e) => e.message,
            'message',
            allOf(
                contains('服务商网关超时'), contains('504'), contains('gateway-1')))));
    expect(requests, 1);
  });

  test('image profile validates URLs, custom paths and round trips', () {
    expect(imageProfile.isComplete, isTrue);
    expect(imageProfile.endpoint(ImageTaskMode.textToImage).toString(),
        'https://example.test/v1/images/generations');
    expect(imageProfile.endpoint(ImageTaskMode.edit).toString(),
        'https://example.test/v1/images/edits');
    expect(ImageApiProfile.fromJson(imageProfile.toJson()).toJson(),
        imageProfile.toJson());
    final custom = ImageApiProfile.fromJson(
        {...imageProfile.toJson(), 'generationPath': '/custom/generate'});
    expect(custom.endpoint(ImageTaskMode.textToImage).toString(),
        'https://example.test/v1/custom/generate');
    for (final invalid in [
      'not-a-url',
      'file:///etc/passwd',
      'https://example.test/v1?key=x'
    ]) {
      expect(
          ImageApiProfile.fromJson(
              {...imageProfile.toJson(), 'baseUrl': invalid}).isComplete,
          isFalse);
    }
  });

  test('text generation uses JSON and omits unsupported default options',
      () async {
    late http.Request sent;
    final api = ImageApiService(
        clientFactory: () => MockClient((request) async {
              sent = request;
              return imageResponse();
            }));
    final images = await api.generate(
        profile: imageProfile,
        mode: ImageTaskMode.textToImage,
        prompt: '  a landscape  ');
    expect(sent.headers['authorization'], 'Bearer test-secret');
    expect(jsonDecode(sent.body),
        {'model': 'image-model', 'prompt': 'a landscape', 'n': 1});
    expect(images.single.bytes, [1, 2, 3]);
    expect(images.single.revisedPrompt, 'revised');
  });

  test('image-to-image and edit upload PNG, edit alone includes mask',
      () async {
    for (final mode in [ImageTaskMode.imageToImage, ImageTaskMode.edit]) {
      late http.Request sent;
      final api = ImageApiService(
          clientFactory: () => MockClient((request) async {
                sent = request;
                return imageResponse();
              }));
      await api.generate(
          profile: imageProfile,
          mode: mode,
          prompt: 'change the sky',
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          mask: Uint8List.fromList([4, 5, 6]),
          size: '1024x1024',
          quality: 'high',
          count: 2);
      expect(sent.url.toString(), 'https://example.test/v1/images/edits');
      expect(sent.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      final body = latin1.decode(sent.bodyBytes);
      expect(body, contains('name="image"; filename="reference.png"'));
      expect(body, contains('content-type: image/png'));
      expect(body.contains('name="mask"; filename="mask.png"'),
          mode == ImageTaskMode.edit);
      expect(body, contains('1024x1024'));
      expect(body, contains('high'));
    }
  });

  test('multiple references are sent in order, with mask only for edit',
      () async {
    for (final mode in [ImageTaskMode.imageToImage, ImageTaskMode.edit]) {
      late http.Request sent;
      final api = ImageApiService(
          clientFactory: () => MockClient((request) async {
                sent = request;
                return imageResponse();
              }));
      await api.generate(
          profile: imageProfile,
          mode: mode,
          prompt: 'combine the references',
          images: [
            Uint8List.fromList(utf8.encode('first-image-bytes')),
            Uint8List.fromList(utf8.encode('second-image-bytes')),
            Uint8List.fromList(utf8.encode('third-image-bytes'))
          ],
          mask: Uint8List.fromList(utf8.encode('first-image-mask')),
          size: '1536x864');
      final body = latin1.decode(sent.bodyBytes);
      expect(RegExp('name="image\\[\\]"; filename=').allMatches(body),
          hasLength(3));
      expect(body, isNot(contains('name="image";')));
      expect(body.indexOf('first-image-bytes'),
          lessThan(body.indexOf('second-image-bytes')));
      expect(body.indexOf('second-image-bytes'),
          lessThan(body.indexOf('third-image-bytes')));
      expect(body.contains('first-image-mask'), mode == ImageTaskMode.edit);
      expect(body, contains('1536x864'));
    }
  });

  test('empty reference entries and too many images fail before network access',
      () async {
    var calls = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async {
              calls++;
              return imageResponse();
            }));
    for (final images in [
      <Uint8List>[Uint8List(0)],
      List.generate(17, (_) => Uint8List.fromList([1, 2, 3]))
    ]) {
      await expectLater(
          api.generate(
              profile: imageProfile,
              mode: ImageTaskMode.imageToImage,
              prompt: 'test',
              images: images),
          throwsA(isA<ImageApiException>()));
    }
    expect(calls, 0);
  });

  test('URL results download without sending the API key', () async {
    final api = ImageApiService(
        clientFactory: () => MockClient((request) async {
              if (request.method == 'POST') {
                return http.Response(
                    jsonEncode({
                      'data': [
                        {'url': 'https://cdn.test/image.png'}
                      ]
                    }),
                    200);
              }
              expect(request.headers.containsKey('authorization'), isFalse);
              expect(request.url.host, 'cdn.test');
              return http.Response.bytes([1, 2, 3], 200);
            }));
    final images = await api.generate(
        profile: imageProfile, mode: ImageTaskMode.textToImage, prompt: 'test');
    expect(images.single.bytes, [1, 2, 3]);
  });

  test('errors include HTTP status but redact API credentials', () async {
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'message': 'invalid key test-secret'}
            }),
            401)));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test'),
        throwsA(isA<ImageApiException>().having((e) => e.message, 'message',
            allOf(contains('401'), isNot(contains('test-secret'))))));
  });

  test('missing references and malformed or empty responses fail clearly',
      () async {
    var calls = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async {
              calls++;
              return http.Response('{}', 200);
            }));
    await expectLater(
        api.generate(
            profile: imageProfile, mode: ImageTaskMode.edit, prompt: 'test'),
        throwsA(isA<ImageApiException>()));
    expect(calls, 0);
    for (final payload in [
      '{}',
      'not json',
      '{"data":[{"b64_json":"invalid!!!"}]}'
    ]) {
      final service = ImageApiService(
          clientFactory: () =>
              MockClient((_) async => http.Response(payload, 200)));
      await expectLater(
          service.generate(
              profile: imageProfile,
              mode: ImageTaskMode.textToImage,
              prompt: 'test'),
          throwsA(isA<ImageApiException>()));
    }
  });

  test('cancellation releases a stalled request and permits retry', () async {
    final stalled = Completer<http.Response>();
    var calls = 0;
    final api = ImageApiService(
        clientFactory: () => MockClient((_) async =>
            ++calls == 1 ? await stalled.future : imageResponse()));
    final pending = api.generate(
        profile: imageProfile, mode: ImageTaskMode.textToImage, prompt: 'test');
    final check = expectLater(
        pending,
        throwsA(isA<ImageApiException>()
            .having((e) => e.message, 'message', contains('停止'))));
    api.cancel();
    await check;
    expect(
        await api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'retry'),
        hasLength(1));
    stalled.complete(imageResponse());
  });

  test('timeout terminates the request with a usable error', () async {
    final stalled = Completer<http.Response>();
    final api = ImageApiService(
        timeout: const Duration(milliseconds: 10),
        clientFactory: () => MockClient((_) => stalled.future));
    await expectLater(
        api.generate(
            profile: imageProfile,
            mode: ImageTaskMode.textToImage,
            prompt: 'test'),
        throwsA(isA<ImageApiException>()
            .having((e) => e.message, 'message', contains('超时'))));
    stalled.complete(imageResponse());
  });
}

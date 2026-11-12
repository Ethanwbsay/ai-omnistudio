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
import 'package:question_solver/services/image_response_reader.dart';

const profile = ImageApiProfile(
    id: 'stream',
    name: '图片',
    baseUrl: 'https://suoxie.codes/',
    apiKey: 'test-secret',
    model: 'gpt-image-2.5-flare');

String completed(List<int> bytes, {String type = 'image_edit.completed'}) =>
    'event: $type\r\ndata: ${jsonEncode({
          'type': type,
          'b64_json': base64Encode(bytes),
          'revised_prompt': '中文'
        })}\r\n\r\n';

http.StreamedResponse events(Stream<List<int>> stream) =>
    http.StreamedResponse(stream, 200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'});

class SocketOverrides extends HttpOverrides {}

void main() {
  for (final heartbeat in [
    'data:\n\n',
    'data: ping\n\n',
    'event: ping\ndata: waiting\n\n',
    'event: status\ndata: Generating image...\n\n',
    'data: null\n\n',
    'data: {broken gateway frame\n\n',
  ]) {
    test(
        'non-image heartbeat must not terminate before the final image: $heartbeat',
        () async {
      final body = StreamController<List<int>>();
      var finished = false;
      final future = readImageResponse(events(body.stream)).then((response) {
        finished = true;
        return response;
      });
      final check = expectLater(
          future,
          completion(isA<http.Response>().having(
              (r) => jsonDecode(r.body)['data'].single['b64_json'],
              'image',
              'AQID')));
      body.add(utf8.encode(heartbeat));
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      body.add(utf8.encode(completed([1, 2, 3])));
      await check;
      await body.close();
    });
  }
  test('unnamed SSE message can carry a full Images response', () async {
    final response = await readImageResponse(events(
        Stream.value(utf8.encode('data: {"data":[{"b64_json":"AQID"}]}\n\n'))));
    expect(jsonDecode(response.body)['data'].single['b64_json'], 'AQID');
  });
  test(
      'invalid unnamed events alone report counts without copying private content',
      () async {
    await expectLater(
        readImageResponse(events(Stream.value(
            utf8.encode('data: test-secret https://private.test/image\n\n')))),
        throwsA(isA<ImageStreamException>().having(
            (e) => e.message,
            'safe diagnostic',
            allOf(
                contains('0/1'),
                contains('1 个无法解析'),
                isNot(contains('test-secret')),
                isNot(contains('private.test'))))));
  });
  test('invalid final event remains an error even after a valid preview',
      () async {
    await expectLater(
        readImageResponse(events(Stream.value(utf8.encode(
            'event: image_edit.partial_image\ndata: {"b64_json":"AQID"}\n\n'
            'event: image_edit.completed\ndata: {broken\n\n')))),
        throwsA(isA<ImageStreamException>()
            .having((e) => e.message, 'reason', contains('最终图片'))));
  });
  test('unnamed JSON error is propagated after text heartbeats', () async {
    await expectLater(
        readImageResponse(events(Stream.value(utf8.encode(
            'data: ping\n\ndata: {"error":{"message":"upstream failed"}}\n\n')))),
        throwsA(isA<ImageStreamException>()
            .having((e) => e.message, 'reason', 'upstream failed')));
  });
  test(
      'long final JSON survives proxy line folding and bare continuation lines',
      () async {
    final large = base64Encode(List<int>.filled(192, 7));
    final json =
        jsonEncode({'type': 'image_edit.completed', 'b64_json': large});
    final split = json.length ~/ 2;
    final payload =
        'event: image_edit.completed\ndata: ${json.substring(0, split)}\n'
        '${json.substring(split)}\n\n';
    final response =
        await readImageResponse(events(Stream.value(utf8.encode(payload))));
    expect(jsonDecode(response.body)['data'].single['b64_json'], large);
  });
  test(
      'final JSON without a trailing blank line is accepted only when complete',
      () async {
    final json =
        jsonEncode({'type': 'image_generation.completed', 'b64_json': 'AQID'});
    final response = await readImageResponse(events(Stream.value(
        utf8.encode('event: image_generation.completed\ndata: $json'))));
    expect(jsonDecode(response.body)['data'].single['b64_json'], 'AQID');
  });
  test(
      'split final event keeps waiting across blank delimiters until all image data arrives',
      () async {
    final body = StreamController<List<int>>();
    var finished = false;
    final result = readImageResponse(events(body.stream)).then((response) {
      finished = true;
      return response;
    });
    final json =
        jsonEncode({'type': 'image_edit.completed', 'b64_json': 'AQID'});
    final split = json.indexOf('AQID') + 2;
    body.add(utf8.encode(
        'event: image_edit.completed\ndata: ${json.substring(0, split)}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    body.add(utf8.encode(': heartbeat\n\ndata: ${json.substring(split)}\n\n'));
    final response = await result.timeout(const Duration(seconds: 2));
    expect(jsonDecode(response.body)['data'].single['b64_json'], 'AQID');
    await body.close();
  });
  test(
      'damaged final frame can be followed by a separate valid completed event',
      () async {
    final payload =
        'event: image_edit.completed\ndata: {broken\n\n${completed([1, 2, 3])}';
    final response =
        await readImageResponse(events(Stream.value(utf8.encode(payload))));
    expect(jsonDecode(response.body)['data'].single['b64_json'], 'AQID');
  });
  test(
      'invalid final JSON diagnostic exposes position and size but never response content',
      () async {
    const payload =
        'event: image_edit.completed\ndata: {"b64_json":"test-secret https://private.test/image\n\n';
    await expectLater(
        readImageResponse(events(Stream.value(utf8.encode(payload)))),
        throwsA(isA<ImageStreamException>().having(
            (e) => e.message,
            'safe diagnostic',
            allOf(
                contains('最终图片事件'),
                contains('错误位置'),
                contains('事件'),
                isNot(contains('test-secret')),
                isNot(contains('private.test'))))));
  });
  test(
      'physical newline outside Base64 must not silently alter other JSON strings',
      () async {
    const payload =
        'event: image_edit.completed\ndata: {"b64_json":"AQID","revised_prompt":"first\ndata: second"}\n\n';
    await expectLater(
        readImageResponse(events(Stream.value(utf8.encode(payload)))),
        throwsA(isA<ImageStreamException>()));
  });
  test(
      'known provider bare URL gets /v1 without doubling or overriding custom paths',
      () {
    expect(profile.endpoint(ImageTaskMode.edit).path, '/v1/images/edits');
    expect(profile.endpoint(ImageTaskMode.textToImage).path,
        '/v1/images/generations');
    for (final prefix in [
      'https://suoxie.codes/v1/',
      'https://suoxie.codes/proxy/v1'
    ]) {
      final p =
          ImageApiProfile.fromJson({...profile.toJson(), 'baseUrl': prefix});
      expect(p.endpoint(ImageTaskMode.edit).path,
          '${Uri.parse(prefix).path.replaceAll(RegExp(r'/+$'), '')}/images/edits');
    }
    final custom = ImageApiProfile.fromJson(
        {...profile.toJson(), 'editPath': '/v1/images/edits'});
    expect(custom.endpoint(ImageTaskMode.edit).path, '/v1/images/edits');
    final other = ImageApiProfile.fromJson(
        {...profile.toJson(), 'baseUrl': 'https://example.test/'});
    expect(other.endpoint(ImageTaskMode.edit).path, '/images/edits');
    expect(other.usesStreaming, false);
    expect(
        ImageApiProfile.fromJson({...profile.toJson(), 'model': 'dall-e-2'})
            .usesStreaming,
        false);
  });

  test(
      'old profiles auto-enable known provider streaming; override round-trips',
      () {
    final legacy = profile.toJson()..remove('responseMode');
    expect(ImageApiProfile.fromJson(legacy).usesStreaming, true);
    final manual =
        ImageApiProfile.fromJson({...profile.toJson(), 'responseMode': 'json'});
    expect(manual.usesStreaming, false);
    expect(ImageApiProfile.fromJson(manual.toJson()).responseMode, 'json');
    expect(
        ImageApiProfile.fromJson(
            {...profile.toJson(), 'responseMode': 'unknown'}).isComplete,
        false);
  });

  test(
      'stream request fields use JSON and multipart and accept a JSON fallback once',
      () async {
    for (final mode in ImageTaskMode.values) {
      var calls = 0;
      final api = ImageApiService(
          clientFactory: () => MockClient((request) async {
                calls++;
                expect(
                    request.url.path,
                    mode == ImageTaskMode.textToImage
                        ? '/v1/images/generations'
                        : '/v1/images/edits');
                expect(
                    request.headers['accept'], contains('text/event-stream'));
                if (mode == ImageTaskMode.textToImage) {
                  expect(jsonDecode(request.body)['stream'], true);
                  expect(jsonDecode(request.body)['partial_images'], 1);
                } else {
                  expect(request.body, contains('name="stream"\r\n\r\ntrue'));
                  expect(
                      request.body, contains('name="partial_images"\r\n\r\n1'));
                  expect(request.body, contains('name="image[]"'));
                }
                return http.Response(
                    jsonEncode({
                      'data': [
                        {'b64_json': 'AQID'}
                      ]
                    }),
                    200);
              }));
      final result = await api
          .generate(profile: profile, mode: mode, prompt: 'test', images: [
        Uint8List.fromList([1]),
        Uint8List.fromList([2])
      ]);
      expect(result.single.bytes, [1, 2, 3]);
      expect(calls, 1);
    }
  });

  test(
      'fragmented UTF8, CRLF, comments and partial previews wait for final event before EOF',
      () async {
    final body = StreamController<List<int>>();
    var finished = false;
    var received = 0;
    final future =
        readImageResponse(events(body.stream), onBytes: (n) => received = n)
            .then((result) {
      finished = true;
      return result;
    });
    const preview =
        ': keepalive\r\n\r\nevent: image_edit.partial_image\r\ndata: {"b64_json":"cHJldmlldw=="}\r\n\r\n';
    body.add(utf8.encode(preview));
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    final bytes = utf8.encode(completed([1, 2, 3]));
    for (final byte in bytes) {
      body.add([byte]);
    }
    final response = await future.timeout(const Duration(seconds: 2));
    expect(jsonDecode(response.body)['data'].single['b64_json'], 'AQID');
    expect(jsonDecode(response.body)['data'].single['revised_prompt'], '中文');
    // LineSplitter can dispatch a CRLF delimiter as soon as CR arrives; the
    // remaining LF need not be read after the final image is complete.
    expect(
        received,
        inInclusiveRange(utf8.encode(preview).length + bytes.length - 1,
            utf8.encode(preview).length + bytes.length));
    await body.close();
  });

  test(
      'multiple final images and multiline event data retain all requested outputs',
      () async {
    final body = StreamController<List<int>>();
    final result = readImageResponse(events(body.stream), expectedCount: 2);
    body.add(utf8.encode(completed([1])));
    body.add(utf8.encode(
        'event: image_generation.completed\ndata: {"b64_json":\ndata: "Ag=="}\n\n'));
    final response = await result;
    expect(jsonDecode(response.body)['data'].map((e) => e['b64_json']),
        ['AQ==', 'Ag==']);
    await body.close();
  });

  for (final text in [
    'event: image_edit.partial_image\ndata: {"b64_json":"AQID"}\n\n',
    'data: [DONE]\n\n',
    'event: image_edit.completed\ndata: {"b64_json":\n\n',
    'event: image_edit.completed\ndata: {}\n\n',
  ]) {
    test('incomplete or invalid SSE cannot be saved: ${text.length}', () async {
      await expectLater(
          readImageResponse(events(Stream.value(utf8.encode(text)))),
          throwsA(isA<ImageStreamException>()));
    });
  }

  test('stream error stops and never includes preview output', () async {
    const payload =
        'event: error\ndata: {"error":{"message":"upstream unavailable"}}\n\n';
    await expectLater(
        readImageResponse(events(Stream.value(utf8.encode(payload)))),
        throwsA(isA<ImageStreamException>()
            .having((e) => e.message, 'reason', 'upstream unavailable')));
  });

  test(
      'real HTTP chunked response flushes heartbeat then final without closing connection',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    final listener = server.listen((request) async {
      calls++;
      await request.drain<void>();
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.bufferOutput = false;
      request.response.write(': alive\n\n');
      request.response.write('data:\n\nevent: ping\ndata: waiting\n\n');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      request.response.write(completed([1, 2, 3]));
      await request.response.flush();
      // Deliberately leave the response open, as gateways can do after completion.
    });
    final stages = <ImageRequestStage>[];
    final local = ImageApiProfile.fromJson({
      ...profile.toJson(),
      'baseUrl': 'http://127.0.0.1:${server.port}/v1',
      'responseMode': 'stream'
    });
    final api = ImageApiService(
        timeout: const Duration(seconds: 2),
        clientFactory: () =>
            IOClient(SocketOverrides().createHttpClient(null)));
    try {
      final result = await api.generate(
          profile: local,
          mode: ImageTaskMode.edit,
          prompt: 'test',
          images: [
            Uint8List.fromList([1])
          ],
          onProgress: stages.add);
      expect(result.single.bytes, [1, 2, 3]);
      expect(stages, contains(ImageRequestStage.receiving));
      expect(calls, 1);
    } finally {
      api.dispose();
      await listener.cancel();
      await server.close(force: true);
    }
  });
}

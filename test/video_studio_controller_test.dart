import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:question_solver/models/video_api_profile.dart';
import 'package:question_solver/services/video_api_service.dart';
import 'package:question_solver/services/video_store.dart';
import 'package:question_solver/services/video_studio_controller.dart';
import 'video_api_service_test.dart' show profile, mp4Header;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late VideoStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('video-jobs-');
    store = VideoStore(directory: dir);
    await store.saveProfiles([profile(VideoProvider.grok)]);
  });
  tearDown(() async => dir.delete(recursive: true));

  test(
      'task ID is persisted before polling, survives restart and resumes without POST',
      () async {
    final pending = Completer<void>();
    var posts = 0;
    final controller = VideoStudioController(
        store: store,
        pollInterval: const Duration(hours: 1),
        service: VideoApiService(
            clientFactory: () => MockClient((r) async {
                  if (r.method == 'POST') {
                    posts++;
                    return http.Response(
                        '{"request_id":"persisted-task"}', 200);
                  }
                  expect(
                      (await store.loadJobs()).single.taskId, 'persisted-task');
                  pending.complete();
                  return http.Response('{"status":"pending"}', 200);
                })));
    await controller.load();
    final generating = controller.generate(
        profile: controller.profiles.single,
        prompt: 'cat',
        options: const VideoOptions());
    await pending.future;
    controller.pause();
    await generating;
    controller.dispose();
    expect((await store.loadJobs()).single.canResume, true);
    final requests = <http.Request>[];
    final restored = VideoStudioController(
        store: store,
        service: VideoApiService(
            clientFactory: () => MockClient((r) async {
                  requests.add(r);
                  if (r.url.host == 'cdn.example') {
                    return http.Response.bytes(mp4Header, 200);
                  }
                  return http.Response(
                      '{"status":"done","video":{"url":"https://cdn.example/v.mp4"}}',
                      200);
                })));
    await restored.load();
    await restored.resume(restored.jobs.single);
    expect(restored.error, isNull);
    expect(restored.jobs.single.localPath, isNotEmpty);
    expect(await File(restored.jobs.single.localPath).exists(), true);
    expect(requests.every((r) => r.method == 'GET'), true);
    expect(requests.last.headers.containsKey('Authorization'), false);
    expect(posts, 1);
    final raw = await File('${dir.path}/video_studio/jobs.json').readAsString();
    expect(raw.contains('test-secret'), false);
    restored.dispose();
  });

  test('failed download retains successful remote task for a new signed URL',
      () async {
    var downloadCalls = 0, postCalls = 0;
    final controller = VideoStudioController(
        store: store,
        service: VideoApiService(
            clientFactory: () => MockClient((r) async {
                  if (r.method == 'POST') {
                    postCalls++;
                    return http.Response('{"request_id":"id"}', 200);
                  }
                  if (r.url.host == 'cdn.example') {
                    downloadCalls++;
                    return downloadCalls == 1
                        ? http.Response('expired', 403)
                        : http.Response.bytes(mp4Header, 200);
                  }
                  return http.Response(
                      '{"status":"done","video":{"url":"https://cdn.example/v.mp4"}}',
                      200);
                })));
    await controller.load();
    await controller.generate(
        profile: controller.profiles.single,
        prompt: 'cat',
        options: const VideoOptions());
    expect(controller.error, contains('403'));
    expect(controller.jobs.single.canResume, true);
    expect((await store.loadJobs()).single.status, 'done');
    await controller.resume(controller.jobs.single);
    expect(controller.error, isNull);
    expect(controller.jobs.single.localPath, isNotEmpty);
    expect(postCalls, 1);
    controller.dispose();
  });

  test(
      'terminal failure is preserved and does not download or retry generation',
      () async {
    var calls = 0;
    final controller = VideoStudioController(
        store: store,
        service: VideoApiService(
            clientFactory: () => MockClient((r) async {
                  calls++;
                  return http.Response(
                      r.method == 'POST'
                          ? '{"request_id":"id"}'
                          : '{"status":"failed","error":{"message":"quota"}}',
                      200);
                })));
    await controller.load();
    await controller.generate(
        profile: controller.profiles.single,
        prompt: 'cat',
        options: const VideoOptions());
    expect(controller.jobs.single.status, 'failed');
    expect(controller.jobs.single.canResume, false);
    expect(controller.error, contains('quota'));
    await controller.resume(controller.jobs.single);
    expect(calls, 2);
    controller.dispose();
  });

  test(
      'navigation during submission still saves returned ID and avoids background polling',
      () async {
    final result = Completer<http.Response>();
    final controller = VideoStudioController(
        store: store,
        service: VideoApiService(
            clientFactory: () => MockClient((r) async {
                  expect(r.method, 'POST');
                  return result.future;
                })));
    await controller.load();
    final generating = controller.generate(
        profile: controller.profiles.single,
        prompt: 'cat',
        options: const VideoOptions());
    controller.dispose();
    result.complete(http.Response('{"request_id":"navigated-task"}', 200));
    await generating;
    expect((await store.loadJobs()).single.taskId, 'navigated-task');
  });

  test('corrupt history blocks generation until successfully reloaded',
      () async {
    await File('${(await store.folder()).path}/jobs.json')
        .writeAsString('invalid');
    var calls = 0;
    final controller = VideoStudioController(
        store: store,
        service: VideoApiService(
            clientFactory: () => MockClient((_) async {
                  calls++;
                  return http.Response('{}', 200);
                })));
    await controller.load();
    expect(controller.ready, false);
    await controller.generate(
        profile: profile(VideoProvider.grok),
        prompt: 'x',
        options: const VideoOptions());
    expect(calls, 0);
    controller.dispose();
  });

  test(
      'profile and jobs round trip, media deletion never follows arbitrary stored paths',
      () async {
    expect(jsonEncode((await store.loadProfiles()).single.toJson()),
        jsonEncode(profile(VideoProvider.grok).toJson()));
    expect(
        () => store.videoFile('../outside'), throwsA(isA<FormatException>()));
  });
}

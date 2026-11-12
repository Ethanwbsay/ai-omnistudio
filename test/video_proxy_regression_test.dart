import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:question_solver/models/video_api_profile.dart';
import 'package:question_solver/models/video_job.dart';
import 'package:question_solver/services/video_api_service.dart';
import 'package:question_solver/services/video_store.dart';
import 'package:question_solver/services/video_studio_controller.dart';
import 'video_api_service_test.dart' show mp4Header, profile;

const proxy = VideoApiProfile(
    id: 'proxy-1',
    name: '偏爱 AI',
    provider: VideoProvider.grok,
    baseUrl: 'https://chat.yueyued.top/api/openai/v1',
    apiKey: 'test-key',
    model: 'grok-imagine-video',
    submitPath: 'videos/generations',
    queryPath: 'videos/{id}');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'website proxy uses grok_model and stable client ID across separate HTTP clients',
      () async {
    final requests = <http.Request>[];
    final service = VideoApiService(
        clientFactory: () => MockClient((r) async {
              requests.add(r);
              if (r.method == 'POST') {
                return http.Response(
                    '{"request_id":"grok-task-1-opaque"}', 200);
              }
              if (r.url.queryParameters['grok_model'] != 'grok-imagine-video' ||
                  r.headers['x-paiai-client-id'] != proxy.proxyClientId) {
                return http.Response(
                    '{"error":{"message":"task_not_exist"}}', 400);
              }
              return http.Response('{"status":"pending"}', 200);
            }));
    final id = await service.submit(
        profile: proxy, prompt: 'cat', options: const VideoOptions());
    expect((await service.query(proxy, id)).status, 'pending');
    expect(requests[0].headers['x-paiai-client-id'],
        requests[1].headers['x-paiai-client-id']);
    expect(requests[1].url.path, '/api/openai/v1/videos/grok-task-1-opaque');
    expect(
        profile(VideoProvider.grok).endpoint(taskId: 'native').hasQuery, false);
  });

  test(
      'old task remains queryable without inventing a new owner; original model is used',
      () async {
    final service = VideoApiService(
        clientFactory: () => MockClient((r) async {
              expect(r.headers.containsKey('x-paiai-client-id'), false);
              expect(r.url.queryParameters['grok_model'],
                  'grok-imagine-video-1.5');
              return http.Response(
                  '{"status":"done","video":{"url":"media/videos/id"}}', 200);
            }));
    expect(
        (await service.query(proxy, 'old-task',
                taskModel: 'grok-imagine-video-1.5', proxyClientId: ''))
            .complete,
        true);
  });

  test('proxy accepts website-compatible response envelopes and success labels',
      () async {
    for (final data in [
      {'status': 'completed', 'video_url': '/v1/media/videos/id'},
      {
        'state': 'success',
        'data': {'url': 'media/videos/id'}
      },
      {
        'data': {
          'status': 'ready',
          'video': {'url': 'https://cdn.example/v.mp4'}
        }
      },
      {
        'video': {'url': '/api/openai/v1/media/videos/id'}
      },
    ]) {
      final service = VideoApiService(
          clientFactory: () =>
              MockClient((_) async => http.Response(jsonEncode(data), 200)));
      final result = await service.query(proxy, 'id');
      expect(result.complete, true);
      expect(result.url, isNotEmpty);
    }
  });

  test(
      'relative proxy media is authenticated; redirected CDN never receives Key or client ID',
      () async {
    final dir = await Directory.systemTemp.createTemp('proxy-media-');
    addTearDown(() => dir.delete(recursive: true));
    for (final url in [
      'media/videos/id',
      '/v1/media/videos/id',
      '/api/openai/v1/media/videos/id'
    ]) {
      final requests = <http.Request>[];
      final service = VideoApiService(
          clientFactory: () => MockClient((r) async {
                requests.add(r);
                if (r.url.host == 'chat.yueyued.top') {
                  expect(r.url.path, '/api/openai/v1/media/videos/id');
                  expect(r.url.queryParameters['grok_model'],
                      'grok-imagine-video');
                  expect(r.headers['Authorization'], 'Bearer test-key');
                  expect(r.headers['x-paiai-client-id'], proxy.proxyClientId);
                  expect(r.followRedirects, false);
                  return http.Response('', 302,
                      headers: {'location': 'https://cdn.example/video.mp4'});
                }
                expect(r.headers.containsKey('Authorization'), false);
                expect(r.headers.containsKey('x-paiai-client-id'), false);
                return http.Response.bytes(mp4Header, 200);
              }));
      await service.download(url, File('${dir.path}/video.mp4'),
          profile: proxy);
      expect(requests.length, 2);
    }
  });

  test(
      'matching path on another host does not activate the site-specific protocol',
      () {
    final other = VideoApiProfile(
        id: 'other',
        name: 'Other',
        provider: VideoProvider.grok,
        baseUrl: 'https://other.example/api/openai/v1',
        apiKey: 'test-key',
        model: proxy.model,
        submitPath: proxy.submitPath,
        queryPath: proxy.queryPath);
    expect(other.usesPaiaiProxy, false);
    expect(other.endpoint(taskId: 'id').hasQuery, false);
  });

  test(
      'persisted proxy jobs retain identity and resume using the model that created them',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('proxy-jobs-');
    addTearDown(() => dir.delete(recursive: true));
    final store = VideoStore(directory: dir);
    await store.saveProfiles([proxy]);
    final job = VideoJob(
        id: 'video-1',
        profileId: proxy.id,
        provider: proxy.provider,
        baseUrl: proxy.baseUrl,
        queryPath: proxy.queryPath,
        taskId: 'grok-task-1-opaque',
        prompt: 'cat',
        model: 'grok-imagine-video-1.5',
        mode: '文生视频',
        createdAt: DateTime(2026),
        duration: 5,
        ratio: '16:9',
        resolution: '720p',
        proxyClientId: proxy.proxyClientId);
    await store.saveJobs([job]);
    final requests = <http.Request>[];
    final service = VideoApiService(
        clientFactory: () => MockClient((r) async {
              requests.add(r);
              expect(r.headers['x-paiai-client-id'], job.proxyClientId);
              expect(r.url.queryParameters['grok_model'], job.model);
              return r.url.path.contains('/media/')
                  ? http.Response.bytes(mp4Header, 200)
                  : http.Response(
                      '{"status":"completed","data":{"video_url":"media/videos/id"}}',
                      200);
            }));
    final controller = VideoStudioController(store: store, service: service);
    await controller.load();
    await controller.resume(controller.jobs.single);
    expect(controller.error, isNull);
    expect(controller.jobs.single.localPath, isNotEmpty);
    expect(requests.every((r) => r.method == 'GET'), true);
    expect((await store.loadJobs()).single.proxyClientId, proxy.proxyClientId);
    final legacyJson = job.toJson()..remove('proxyClientId');
    expect(VideoJob.fromJson(legacyJson).proxyClientId, '');
    controller.dispose();
  });
}

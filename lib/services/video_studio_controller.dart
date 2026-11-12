import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/video_api_profile.dart';
import '../models/video_job.dart';
import 'video_api_service.dart';
import 'video_store.dart';

class VideoStudioController extends ChangeNotifier {
  VideoStudioController(
      {VideoStore? store,
      VideoApiService? service,
      this.pollInterval = const Duration(seconds: 5),
      this.pollTimeout = const Duration(minutes: 20)})
      : store = store ?? VideoStore(),
        service = service ?? VideoApiService();
  final VideoStore store;
  final VideoApiService service;
  final Duration pollInterval, pollTimeout;
  List<VideoApiProfile> profiles = [];
  List<VideoJob> jobs = [];
  bool loading = true, ready = false, busy = false, submitting = false;
  String? error, activeJobId;
  bool _disposed = false, _paused = false;
  Completer<void>? _wake;
  Future<void> _writes = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      profiles = await store.loadProfiles();
      jobs = await store.loadJobs();
      ready = true;
      error = null;
    } catch (_) {
      error = '视频配置或任务记录读取失败，请重试。';
    }
    loading = false;
    _notify();
  }

  Future<void> saveProfile(VideoApiProfile profile) async {
    final values = [...profiles.where((e) => e.id != profile.id), profile];
    await store.saveProfiles(values);
    profiles = values;
    _notify();
  }

  Future<void> deleteProfile(String id) async {
    final values = profiles.where((e) => e.id != id).toList();
    await store.saveProfiles(values);
    profiles = values;
    _notify();
  }

  // Serialize snapshots so a pause/navigation cannot race a status update.
  Future<void> _save() {
    final snapshot = List<VideoJob>.of(jobs);
    final write = _writes.then((_) => store.saveJobs(snapshot));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _update(VideoJob job) async {
    jobs = jobs.map((e) => e.id == job.id ? job : e).toList();
    _notify();
    await _save();
  }

  Future<void> deleteJob(VideoJob job) async {
    if (busy) return;
    final values = jobs.where((e) => e.id != job.id).toList();
    await store.saveJobs(values);
    jobs = values;
    _notify();
    await store.deleteFile(job);
  }

  Future<void> generate(
      {required VideoApiProfile profile,
      required String prompt,
      required VideoOptions options,
      String? image}) async {
    if (busy || !ready) return;
    busy = submitting = true;
    _paused = false;
    error = null;
    _notify();
    try {
      final taskId = await service.submit(
          profile: profile, prompt: prompt, options: options, image: image);
      final job = VideoJob(
          id: 'video-${DateTime.now().microsecondsSinceEpoch}',
          profileId: profile.id,
          provider: profile.provider,
          baseUrl: profile.baseUrl,
          queryPath: profile.queryPath,
          taskId: taskId,
          prompt: prompt.trim(),
          model: profile.model,
          mode: image == null ? '文生视频' : '图生视频',
          createdAt: DateTime.now(),
          duration: options.duration,
          ratio: image != null && profile.provider == VideoProvider.ark
              ? 'adaptive'
              : options.ratio,
          resolution: options.resolution,
          proxyClientId: profile.usesPaiaiProxy ? profile.proxyClientId : '');
      jobs = [job, ...jobs];
      activeJobId = job.id;
      submitting = false;
      _notify();
      await _save();
      if (!_disposed && !_paused) await _track(profile, job);
    } catch (e) {
      _report(e);
    } finally {
      submitting = busy = false;
      activeJobId = null;
      _notify();
    }
  }

  Future<void> resume(VideoJob job) async {
    if (busy || !ready || !job.canResume) return;
    final matches = profiles.where((p) =>
        p.id == job.profileId &&
        p.provider == job.provider &&
        p.baseUrl == job.baseUrl &&
        p.queryPath == job.queryPath &&
        p.isComplete);
    if (matches.isEmpty) {
      error = '请恢复此任务原来的视频 API 配置与 Key 后再查询。';
      _notify();
      return;
    }
    busy = true;
    activeJobId = job.id;
    _paused = false;
    error = null;
    _notify();
    try {
      await _track(matches.first, job);
    } catch (e) {
      _report(e);
    } finally {
      busy = false;
      activeJobId = null;
      _notify();
    }
  }

  Future<void> _track(VideoApiProfile profile, VideoJob initial) async {
    var job = initial;
    final deadline = DateTime.now().add(pollTimeout);
    while (!_disposed && !_paused) {
      if (DateTime.now().isAfter(deadline)) {
        throw const VideoApiException('等待已超过 20 分钟，可稍后继续查询此任务。');
      }
      final result = await service.query(profile, job.taskId,
          taskModel: job.model, proxyClientId: job.proxyClientId);
      job = job.copyWith(
          status: result.status, remoteUrl: result.url, error: result.error);
      await _update(job);
      if (_disposed || _paused) return;
      if (result.terminal) {
        error = '${job.statusLabel}：${result.error}';
        return;
      }
      if (result.complete) {
        final file = await store.videoFile(job.id);
        // A file may already exist if saving its history failed on the last run.
        if (!await file.exists()) {
          await service.download(result.url, file,
              profile: profile,
              taskModel: job.model,
              proxyClientId: job.proxyClientId);
        }
        await _update(job.copyWith(localPath: file.path, error: ''));
        return;
      }
      final wake = Completer<void>();
      _wake = wake;
      try {
        await Future.any([Future<void>.delayed(pollInterval), wake.future]);
      } finally {
        _wake = null;
      }
    }
  }

  void _report(Object e) {
    error = e is VideoApiException
        ? e.message
        : e is FormatException
            ? e.message
            : '视频处理或记录保存失败。已返回的任务 ID 保留在任务列表中，请先备份任务 ID。';
  }

  void pause() {
    if (submitting) return;
    _paused = true;
    service.cancel();
    if (_wake != null && !_wake!.isCompleted) _wake!.complete();
    error = '已暂停本地查询，服务端生成仍可能继续；可在任务中继续查询。';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _paused = true;
    if (!submitting) service.dispose();
    if (_wake != null && !_wake!.isCompleted) _wake!.complete();
    super.dispose();
  }
}

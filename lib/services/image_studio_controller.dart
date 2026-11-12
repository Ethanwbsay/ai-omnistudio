import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/image_api_profile.dart';
import '../models/image_artifact.dart';
import 'image_api_service.dart';
import 'image_store.dart';

class _PendingImageDownload {
  const _PendingImageDownload(
      {required this.sources,
      required this.prompt,
      required this.model,
      required this.mode});
  final List<ImageDownloadSource> sources;
  final String prompt, model;
  final ImageTaskMode mode;
}

class ImageStudioController extends ChangeNotifier {
  ImageStudioController({ImageStore? store, ImageApiService? service})
      : store = store ?? ImageStore(),
        service = service ?? ImageApiService();

  final ImageStore store;
  final ImageApiService service;
  List<ImageApiProfile> profiles = [];
  List<ImageArtifact> history = [];
  bool loading = true;
  bool busy = false;
  bool ready = false;
  String? error;
  ImageRequestStage stage = ImageRequestStage.generating;
  int elapsedSeconds = 0;
  Timer? _elapsedTimer;
  _PendingImageDownload? _pendingDownload;
  bool get canRetryDownload => _pendingDownload != null;
  bool _disposed = false;
  int _operation = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      profiles = await store.loadProfiles();
      history = await store.loadHistory();
      ready = true;
    } catch (_) {
      error = '图片配置或历史记录读取失败，请重试。';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> saveProfile(ImageApiProfile profile) async {
    final updated = [...profiles];
    final index = updated.indexWhere((e) => e.id == profile.id);
    if (index < 0) {
      updated.add(profile);
    } else {
      updated[index] = profile;
    }
    await store.saveProfiles(updated);
    profiles = updated;
    _notify();
  }

  Future<void> deleteProfile(String id) async {
    final updated = profiles.where((e) => e.id != id).toList();
    await store.saveProfiles(updated);
    profiles = updated;
    _notify();
  }

  Future<void> deleteArtifact(ImageArtifact item) async {
    final updated = history.where((e) => e.id != item.id).toList();
    await store.saveHistory(updated);
    history = updated;
    _notify();
    await store.deleteFile(item);
  }

  Future<void> generate(
      {required ImageApiProfile profile,
      required ImageTaskMode mode,
      required String prompt,
      required String size,
      required String quality,
      required int count,
      List<Uint8List> images = const [],
      Uint8List? mask}) async {
    if (busy || !ready || canRetryDownload) return;
    stage = ImageRequestStage.generating;
    await _runRequest(
        prompt: prompt,
        model: profile.model,
        mode: mode,
        request: () => service.generate(
            profile: profile,
            mode: mode,
            prompt: prompt,
            size: size,
            quality: quality,
            count: count,
            images: images,
            mask: mask,
            onProgress: _progress));
  }

  void _progress(ImageRequestStage value) {
    if (_disposed) return;
    stage = value;
    _notify();
  }

  Future<void> retryPendingDownload() async {
    final pending = _pendingDownload;
    if (busy || _disposed || pending == null) return;
    stage = ImageRequestStage.downloading;
    await _runRequest(
        prompt: pending.prompt,
        model: pending.model,
        mode: pending.mode,
        request: () =>
            service.retryDownloads(pending.sources, onProgress: _progress));
  }

  void discardPendingDownload() {
    if (busy) return;
    _pendingDownload = null;
    error = null;
    _notify();
  }

  Future<void> _runRequest(
      {required String prompt,
      required String model,
      required ImageTaskMode mode,
      required Future<List<ImageApiResult>> Function() request}) async {
    busy = true;
    error = null;
    elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      _notify();
    });
    final operation = ++_operation;
    _notify();
    final created = <ImageArtifact>[];
    try {
      List<ImageApiResult> results;
      try {
        results = await request();
        _pendingDownload = null;
      } on ImageDownloadException catch (e) {
        results = e.completed;
        if (!_disposed && operation == _operation) {
          _pendingDownload = _PendingImageDownload(
              sources: e.pending, prompt: prompt, model: model, mode: mode);
          error = e.message;
        }
      }
      if (results.isNotEmpty && operation == _operation && !_disposed) {
        _progress(ImageRequestStage.saving);
      }
      for (final result in results) {
        if (operation != _operation || _disposed) break;
        // Validate actual image bytes before adding a file to the local gallery.
        final codec = await ui.instantiateImageCodec(result.bytes);
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        codec.dispose();
        created.add(await store.persist(
            bytes: result.bytes,
            prompt: prompt,
            model: model,
            mode: mode,
            revisedPrompt: result.revisedPrompt));
      }
    } catch (e) {
      if (!_disposed && operation == _operation) {
        error = e is ImageApiException
            ? e.message
            : created.isNotEmpty
                ? '部分图片处理失败，已生成的图片保留在作品中。'
                : '图片处理或本地保存失败，请检查图片格式和可用空间。';
      }
    } finally {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      if (created.isNotEmpty) {
        history = [...created, ...history];
        try {
          await store.saveHistory(history);
        } catch (_) {
          if (!_disposed) error = '图片已生成，但历史记录保存失败。请先导出图片。';
        }
      }
      busy = false;
      _notify();
    }
  }

  void cancel() {
    ++_operation;
    service.cancel();
    error = '已停止生成。';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_operation;
    _elapsedTimer?.cancel();
    service.dispose();
    super.dispose();
  }
}

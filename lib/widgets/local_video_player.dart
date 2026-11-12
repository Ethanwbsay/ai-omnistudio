import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LocalVideoPlayerPage extends StatefulWidget {
  const LocalVideoPlayerPage({super.key, required this.path});
  final String path;
  @override
  State<LocalVideoPlayerPage> createState() => _LocalVideoPlayerPageState();
}

class _LocalVideoPlayerPageState extends State<LocalVideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _player;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      if (!await File(widget.path).exists()) {
        throw const FileSystemException('missing');
      }
      if (!mounted) return;
      final player = VideoPlayerController.file(File(widget.path));
      _player = player;
      await player.initialize();
      if (!mounted) return;
      player.addListener(_changed);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '视频无法播放，请检查文件是否存在；也可导出后使用系统播放器。');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.removeListener(_changed);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
        appBar: AppBar(title: const Text('视频预览')),
        body: _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24), child: Text(_error!)))
            : player == null || !player.value.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                    AspectRatio(
                        aspectRatio: player.value.aspectRatio,
                        child: VideoPlayer(player)),
                    VideoProgressIndicator(player,
                        allowScrubbing: true,
                        padding: const EdgeInsets.all(16)),
                    Text(
                        '${player.value.position.inSeconds} / ${player.value.duration.inSeconds} 秒'),
                    IconButton(
                        tooltip: player.value.isPlaying ? '暂停' : '播放',
                        iconSize: 48,
                        icon: Icon(player.value.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle),
                        onPressed: () async {
                          try {
                            if (player.value.isPlaying) {
                              await player.pause();
                            } else {
                              if (player.value.position >=
                                  player.value.duration) {
                                await player.seekTo(Duration.zero);
                              }
                              await player.play();
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(() => _error = '播放器发生错误，请导出后重试。');
                            }
                          }
                        }),
                    if (player.value.hasError)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('播放器发生错误，请导出后使用系统播放器。')),
                  ]))));
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_api_profile.dart';
import '../models/video_job.dart';

class VideoStore {
  VideoStore({this.directory});
  final Directory? directory;
  static const profilesKey = 'ai_tavern_video_api_profiles';
  Future<List<VideoApiProfile>> loadProfiles() async {
    final raw = (await SharedPreferences.getInstance()).getString(profilesKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) =>
            VideoApiProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveProfiles(List<VideoApiProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        profilesKey, jsonEncode(profiles.map((e) => e.toJson()).toList()))) {
      throw const FileSystemException('视频配置保存失败');
    }
  }

  Future<Directory> folder() async {
    final root = directory ?? await getApplicationDocumentsDirectory();
    return Directory('${root.path}/video_studio')..createSync(recursive: true);
  }

  Future<File> videoFile(String id) async {
    if (!RegExp(r'^video-[0-9]+$').hasMatch(id)) {
      throw const FormatException('视频 ID 无效');
    }
    return File('${(await folder()).path}/$id.mp4');
  }

  Future<List<VideoJob>> loadJobs() async {
    final file = File('${(await folder()).path}/jobs.json');
    if (!await file.exists()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .map((e) => VideoJob.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveJobs(List<VideoJob> jobs) async {
    final dir = await folder();
    final tmp = File('${dir.path}/jobs.tmp');
    await tmp.writeAsString(jsonEncode(jobs.map((e) => e.toJson()).toList()),
        flush: true);
    await tmp.rename('${dir.path}/jobs.json');
  }

  Future<void> deleteFile(VideoJob job) async {
    final file = await videoFile(job.id);
    if (await file.exists()) await file.delete();
  }
}

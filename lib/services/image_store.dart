import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/image_api_profile.dart';
import '../models/image_artifact.dart';

class ImageStore {
  ImageStore({this.directory});
  final Directory? directory;
  static const _profilesKey = 'ai_tavern_image_api_profiles';

  Future<List<ImageApiProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null) return [];
    final items = jsonDecode(raw) as List;
    return items
        .map((e) =>
            ImageApiProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveProfiles(List<ImageApiProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _profilesKey, jsonEncode(profiles.map((e) => e.toJson()).toList()))) {
      throw const FileSystemException('图片 API 配置保存失败');
    }
  }

  Future<Directory> _directory() async {
    final root = directory ?? await getApplicationDocumentsDirectory();
    return Directory('${root.path}/image_studio')..createSync(recursive: true);
  }

  Future<List<ImageArtifact>> loadHistory() async {
    final dir = await _directory();
    final file = File('${dir.path}/history.json');
    if (!await file.exists()) return [];
    final items = jsonDecode(await file.readAsString()) as List;
    return items
        .map((e) => ImageArtifact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveHistory(List<ImageArtifact> items) async {
    final dir = await _directory();
    final temp = File('${dir.path}/history.tmp');
    await temp.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()),
        flush: true);
    await temp.rename('${dir.path}/history.json');
  }

  Future<ImageArtifact> persist(
      {required Uint8List bytes,
      required String prompt,
      required String model,
      required ImageTaskMode mode,
      String revisedPrompt = ''}) async {
    final dir = await _directory();
    final id = 'image-${DateTime.now().microsecondsSinceEpoch}';
    final extension = bytes.length > 12 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'jpg'
        : bytes.length > 12 &&
                ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
            ? 'webp'
            : 'png';
    final file = File('${dir.path}/$id.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return ImageArtifact(
        id: id,
        path: file.path,
        prompt: prompt,
        model: model,
        mode: mode.label,
        createdAt: DateTime.now(),
        revisedPrompt: revisedPrompt);
  }

  Future<void> deleteFile(ImageArtifact item) async {
    final dir = await _directory();
    final file = File(item.path);
    if (file.parent.absolute.path == dir.absolute.path && await file.exists()) {
      await file.delete();
    }
  }
}

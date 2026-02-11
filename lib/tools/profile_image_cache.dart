import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ProfileImageCache {
  ProfileImageCache._();
  static final instance = ProfileImageCache._();

  File? _cachedFile;

  Future<File?> getProfileImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;

    // Return in-memory reference if already resolved this session
    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return _cachedFile;
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/profile_photo.jpg');

    // Serve from disk if already cached
    if (file.existsSync() && file.lengthSync() > 0) {
      _cachedFile = file;
      // Refresh in background so next launch has latest
      _downloadInBackground(photoUrl, file);
      return file;
    }

    // First time — download synchronously
    try {
      final response = await http.get(Uri.parse(photoUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        _cachedFile = file;
        return file;
      }
    } catch (_) {}

    return null;
  }

  void _downloadInBackground(String url, File file) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }
    } catch (_) {}
  }

  /// Call after profile refresh to force re-download next time
  void invalidate() {
    _cachedFile = null;
  }
}

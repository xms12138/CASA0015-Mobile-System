import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

// Handles photo capture via device camera
class CameraService {
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  // Check + request CAMERA runtime permission. Caller short-circuits on
  // false so we can distinguish "permission denied" from "user cancelled
  // the camera intent" (both surface as a null path otherwise).
  Future<bool> ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  // Take a photo using the camera, returns the file path or null if cancelled
  Future<String?> takePhoto() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (image == null) return null;
    return _persist(image);
  }

  // Pick a photo from gallery (useful for testing on desktop/web)
  Future<String?> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (image == null) return null;
    return _persist(image);
  }

  // image_picker drops the file under the OS cache / temp directory, which
  // Android wipes on its own schedule. Copy into the app-private documents
  // directory so the path stored in SQLite stays valid across reboots.
  Future<String> _persist(XFile image) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final ext = p.extension(image.path).isEmpty
        ? '.jpg'
        : p.extension(image.path);
    final newPath = p.join(photosDir.path, '${_uuid.v4()}$ext');
    await File(image.path).copy(newPath);
    return newPath;
  }
}

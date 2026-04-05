import 'package:image_picker/image_picker.dart';

// Handles photo capture via device camera
class CameraService {
  final ImagePicker _picker = ImagePicker();

  // Take a photo using the camera, returns the file path or null if cancelled
  Future<String?> takePhoto() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    return image?.path;
  }

  // Pick a photo from gallery (useful for testing on desktop/web)
  Future<String?> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    return image?.path;
  }
}

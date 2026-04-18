import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Draws a Baidu-style user location marker: a filled dot with a forward-facing
// cone indicating the current compass heading. Returns a BitmapDescriptor that
// can be used as a GoogleMap marker icon.
Future<BitmapDescriptor> buildHeadingMarker({
  Color dotColor = const Color(0xFF2E7D32),
  Color coneColor = const Color(0x552E7D32),
  double size = 48,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);
  final radius = size * 0.16;

  final conePath = Path()
    ..moveTo(center.dx, 0)
    ..lineTo(center.dx - size * 0.22, center.dy)
    ..lineTo(center.dx + size * 0.22, center.dy)
    ..close();
  canvas.drawPath(conePath, Paint()..color = coneColor);

  canvas.drawCircle(center, radius + 3, Paint()..color = Colors.white);
  canvas.drawCircle(center, radius, Paint()..color = dotColor);

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(Uint8List.view(bytes!.buffer));
}

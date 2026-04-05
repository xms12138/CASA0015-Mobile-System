import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import '../services/location_service.dart';
import '../services/camera_service.dart';
import '../models/trip.dart';

enum RecordingStatus { idle, recording, paused }

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final CameraService _cameraService = CameraService();
  final Uuid _uuid = const Uuid();

  RecordingStatus _status = RecordingStatus.idle;
  List<TrackPoint> _trackPoints = [];
  final List<PhotoMarker> _photos = [];
  StreamSubscription? _trackSubscription;
  StreamSubscription? _positionSubscription;

  // Recording timer
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  // Initial camera position (London as default, updates to current location)
  static const LatLng _defaultPosition = LatLng(51.5074, -0.1278);
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPosition!, 15),
      );
    }
  }

  void _startRecording() {
    _locationService.startTracking();

    _trackSubscription = _locationService.trackStream.listen((points) {
      if (mounted) {
        setState(() => _trackPoints = points);
      }
    });

    _positionSubscription = _locationService.positionStream.listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _currentPosition = latLng);
        _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
      }
    });

    // Start elapsed time timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });

    setState(() => _status = RecordingStatus.recording);
  }

  void _pauseRecording() {
    _locationService.pauseTracking();
    _timer?.cancel();
    setState(() => _status = RecordingStatus.paused);
  }

  void _resumeRecording() {
    _locationService.resumeTracking();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
    setState(() => _status = RecordingStatus.recording);
  }

  void _stopRecording() {
    final points = _locationService.stopTracking();
    _trackSubscription?.cancel();
    _positionSubscription?.cancel();
    _timer?.cancel();

    final photoCount = _photos.length;

    setState(() {
      _status = RecordingStatus.idle;
      _trackPoints = [];
      _photos.clear();
      _elapsed = Duration.zero;
    });

    // Show summary (will save to DB in Phase 5)
    if (points.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Journey recorded: ${points.length} points, $photoCount photos'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _takePhoto() async {
    // Use gallery on web/desktop, camera on mobile
    final String? path = kIsWeb
        ? await _cameraService.pickFromGallery()
        : await _cameraService.takePhoto();

    if (path == null || !mounted) return;

    final position = _currentPosition ?? _defaultPosition;
    final photo = PhotoMarker(
      id: _uuid.v4(),
      localPath: path,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
    );

    setState(() => _photos.add(photo));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo added (${_photos.length} total)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // Show full photo in a bottom sheet when marker is tapped
  void _showPhotoPreview(PhotoMarker photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoPreviewSheet(photo: photo),
    );
  }

  // Build map markers from photos
  Set<Marker> _buildPhotoMarkers() {
    return _photos.map((photo) {
      return Marker(
        markerId: MarkerId(photo.id),
        position: LatLng(photo.latitude, photo.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _showPhotoPreview(photo),
      );
    }).toSet();
  }

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:${pad(d.inSeconds.remainder(60))}';
  }

  @override
  void dispose() {
    _locationService.dispose();
    _trackSubscription?.cancel();
    _positionSubscription?.cancel();
    _timer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? _defaultPosition,
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              // Move to current position if already known
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentPosition!, 15),
                );
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // Photo markers on map
            markers: _buildPhotoMarkers(),
            // Draw the route polyline
            polylines: _trackPoints.length >= 2
                ? {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: _trackPoints
                          .map((p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                      color: colorScheme.primary,
                      width: 5,
                    ),
                  }
                : {},
          ),

          // Top bar with recording status
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Status bar
                  if (_status != RecordingStatus.idle)
                    _RecordingStatusBar(
                      status: _status,
                      elapsed: _elapsed,
                      pointCount: _trackPoints.length,
                      formatDuration: _formatDuration,
                    ),
                ],
              ),
            ),
          ),

          // Camera button (only visible during recording)
          if (_status != RecordingStatus.idle)
            Positioned(
              right: 16,
              bottom: 200,
              child: FloatingActionButton(
                heroTag: 'camera',
                onPressed: _takePhoto,
                backgroundColor: colorScheme.surface,
                child: Icon(Icons.camera_alt_rounded, color: colorScheme.primary),
              ),
            ),

          // Re-center button
          Positioned(
            right: 16,
            bottom: 140,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(_currentPosition!),
                  );
                }
              },
              backgroundColor: colorScheme.surface,
              child: Icon(Icons.my_location, color: colorScheme.primary),
            ),
          ),

          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlPanel(
              status: _status,
              colorScheme: colorScheme,
              onStart: _startRecording,
              onPause: _pauseRecording,
              onResume: _resumeRecording,
              onStop: _stopRecording,
            ),
          ),
        ],
      ),
    );
  }
}

// Top status bar showing recording info
class _RecordingStatusBar extends StatelessWidget {
  final RecordingStatus status;
  final Duration elapsed;
  final int pointCount;
  final String Function(Duration) formatDuration;

  const _RecordingStatusBar({
    required this.status,
    required this.elapsed,
    required this.pointCount,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRecording = status == RecordingStatus.recording;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing recording dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isRecording ? Colors.red : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isRecording ? 'Recording' : 'Paused',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Timer
          Icon(Icons.timer_outlined, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(
            formatDuration(elapsed),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          // Point count
          Icon(Icons.location_on_outlined, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(
            '$pointCount pts',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// Bottom control panel with Start/Pause/Stop buttons
class _ControlPanel extends StatelessWidget {
  final RecordingStatus status;
  final ColorScheme colorScheme;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ControlPanel({
    required this.status,
    required this.colorScheme,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: _buildControls(context),
    );
  }

  Widget _buildControls(BuildContext context) {
    switch (status) {
      case RecordingStatus.idle:
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Start Recording', style: TextStyle(fontSize: 16)),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );

      case RecordingStatus.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Stop button
            _CircleButton(
              icon: Icons.stop_rounded,
              color: Colors.red,
              label: 'Stop',
              onTap: () => _confirmStop(context),
            ),
            // Pause button
            _CircleButton(
              icon: Icons.pause_rounded,
              color: Colors.orange,
              label: 'Pause',
              onTap: onPause,
            ),
          ],
        );

      case RecordingStatus.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Stop button
            _CircleButton(
              icon: Icons.stop_rounded,
              color: Colors.red,
              label: 'Stop',
              onTap: () => _confirmStop(context),
            ),
            // Resume button
            _CircleButton(
              icon: Icons.play_arrow_rounded,
              color: colorScheme.primary,
              label: 'Resume',
              onTap: onResume,
            ),
          ],
        );
    }
  }

  void _confirmStop(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Journey?'),
        content: const Text('Do you want to stop recording and save this journey?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onStop();
            },
            child: const Text('Save & Stop'),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Bottom sheet for previewing a photo when its marker is tapped
class _PhotoPreviewSheet extends StatelessWidget {
  final PhotoMarker photo;

  const _PhotoPreviewSheet({required this.photo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Photo
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: kIsWeb
                        ? Image.network(photo.localPath, fit: BoxFit.contain)
                        : Image.file(File(photo.localPath), fit: BoxFit.contain),
                  ),
                ),
              ),
              // Photo info
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${photo.latitude.toStringAsFixed(4)}, ${photo.longitude.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Icon(Icons.access_time, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
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

  RecordingStatus _status = RecordingStatus.idle;
  List<TrackPoint> _trackPoints = [];
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

    setState(() {
      _status = RecordingStatus.idle;
      _trackPoints = [];
      _elapsed = Duration.zero;
    });

    // Show summary (will save to DB in Phase 5)
    if (points.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Journey recorded: ${points.length} points'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';

// GPS tracking service: handles permissions, the always-on location stream,
// and optional track accumulation during a recording session.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  bool _isTracking = false;

  // Last fix that passed both gates. Used by the speed gate regardless of
  // whether we're currently accumulating track points, so idle live updates
  // also benefit from noise filtering.
  Position? _lastAcceptedPosition;
  DateTime? _lastAcceptedAt;

  final List<TrackPoint> _trackPoints = [];
  final _trackController = StreamController<List<TrackPoint>>.broadcast();
  final _positionController = StreamController<Position>.broadcast();

  // Huawei devices w/o Google Play Services fall back to the native Android
  // LocationManager, which mixes GPS + NETWORK providers without any fusion.
  // NETWORK fixes are cell-tower / WiFi triangulations accurate only to
  // hundreds of metres — those show up as sudden "teleport" points. Gate 1
  // drops low-confidence fixes; gate 2 drops physically impossible jumps.
  static const double _maxAcceptableAccuracyMeters = 30.0;
  static const double _maxImpliedSpeedMps = 56.0; // ~200 km/h

  // EMA smoothing on lat/lng for track points only. Without this, walking
  // a straight line renders as a wavy curve because each fix carries ±5-15m
  // noise. Live position stream stays raw so the self-marker follows
  // without perceptible lag; the smoothed values are used only when
  // accumulating the persisted track.
  static const double _trackSmoothingAlpha = 0.35;
  double? _smoothedLat;
  double? _smoothedLng;

  // Emits the full list of track points whenever a new point is added
  Stream<List<TrackPoint>> get trackStream => _trackController.stream;

  // Emits individual position updates (for centering the map)
  Stream<Position> get positionStream => _positionController.stream;

  List<TrackPoint> get trackPoints => List.unmodifiable(_trackPoints);

  // Check and request location permission
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Build platform-specific location settings.
  // Android: force native LocationManager to avoid relying on Google Play Services
  // (important for devices without full GMS, e.g. Huawei/HarmonyOS).
  LocationSettings _settings({int distanceFilter = 0}) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 2),
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
  }

  // Get the current position once
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(locationSettings: _settings());
  }

  // Start the always-on position stream feeding the self-marker and
  // (when recording) the track. Idempotent — repeat calls are no-ops
  // while a subscription exists.
  Future<bool> startLiveUpdates() async {
    if (_positionSubscription != null) return true;
    final ok = await requestPermission();
    if (!ok) return false;
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _settings(distanceFilter: 5),
    ).listen(_onPosition);
    return true;
  }

  void stopLiveUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _lastAcceptedPosition = null;
    _lastAcceptedAt = null;
  }

  void _onPosition(Position position) {
    if (position.accuracy > _maxAcceptableAccuracyMeters) return;

    final now = DateTime.now();
    final prev = _lastAcceptedPosition;
    final prevAt = _lastAcceptedAt;
    if (prev != null && prevAt != null) {
      final dtSec = now.difference(prevAt).inMilliseconds / 1000.0;
      if (dtSec > 0) {
        final metres = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          position.latitude,
          position.longitude,
        );
        if (metres / dtSec > _maxImpliedSpeedMps) return;
      }
    }

    _lastAcceptedPosition = position;
    _lastAcceptedAt = now;
    _positionController.add(position);

    if (_isTracking) {
      if (_smoothedLat == null) {
        _smoothedLat = position.latitude;
        _smoothedLng = position.longitude;
      } else {
        _smoothedLat = _smoothedLat! * (1 - _trackSmoothingAlpha) +
            position.latitude * _trackSmoothingAlpha;
        _smoothedLng = _smoothedLng! * (1 - _trackSmoothingAlpha) +
            position.longitude * _trackSmoothingAlpha;
      }
      final point = TrackPoint(
        latitude: _smoothedLat!,
        longitude: _smoothedLng!,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: now,
      );
      _trackPoints.add(point);
      _trackController.add(List.unmodifiable(_trackPoints));
    }
  }

  // Begin a recording session. Live updates are kept on so the self-marker
  // continues to follow after stop / pause.
  void startTracking() {
    _trackPoints.clear();
    _smoothedLat = null;
    _smoothedLng = null;
    _isTracking = true;
    // Fire-and-forget; permission is expected to be granted already.
    startLiveUpdates();
  }

  // Pause point accumulation without stopping the feed. The self-marker
  // keeps following so the user can see they're still being located.
  void pauseTracking() {
    _isTracking = false;
  }

  void resumeTracking() {
    _isTracking = true;
  }

  // End the recording session and return the collected points. Live
  // updates keep running — they're torn down by dispose() or stopLiveUpdates().
  List<TrackPoint> stopTracking() {
    _isTracking = false;
    return List.unmodifiable(_trackPoints);
  }

  // Clean up resources
  void dispose() {
    _positionSubscription?.cancel();
    _trackController.close();
    _positionController.close();
  }
}

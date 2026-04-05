import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';

// GPS tracking service: handles permissions, location stream, and track recording
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final List<TrackPoint> _trackPoints = [];
  final _trackController = StreamController<List<TrackPoint>>.broadcast();
  final _positionController = StreamController<Position>.broadcast();

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

  // Get the current position once
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  // Start continuous GPS tracking
  void startTracking() {
    _trackPoints.clear();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // minimum distance (meters) before update
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      final point = TrackPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: DateTime.now(),
      );

      _trackPoints.add(point);
      _trackController.add(List.unmodifiable(_trackPoints));
      _positionController.add(position);
    });
  }

  // Pause tracking (stop listening but keep existing points)
  void pauseTracking() {
    _positionSubscription?.pause();
  }

  // Resume tracking after pause
  void resumeTracking() {
    _positionSubscription?.resume();
  }

  // Stop tracking and return all recorded points
  List<TrackPoint> stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    return List.unmodifiable(_trackPoints);
  }

  // Clean up resources
  void dispose() {
    _positionSubscription?.cancel();
    _trackController.close();
    _positionController.close();
  }
}

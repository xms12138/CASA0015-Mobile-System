// Data model for a recorded trip
class Trip {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final List<TrackPoint> trackPoints;
  final List<PhotoMarker> photos;
  final List<WeatherRecord> weatherRecords;

  Trip({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    this.trackPoints = const [],
    this.photos = const [],
    this.weatherRecords = const [],
  });
}

// A single GPS point in the track
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    required this.timestamp,
  });
}

// A photo taken during the trip, pinned to a location
class PhotoMarker {
  final String id;
  final String localPath;
  final String? remoteUrl;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  PhotoMarker({
    required this.id,
    required this.localPath,
    this.remoteUrl,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

// Environmental data snapshot recorded during the trip
class WeatherRecord {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? temperature;
  final String? weatherDescription;
  final double? humidity;
  final double? windSpeed;
  final int? aqi; // Air Quality Index

  WeatherRecord({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.temperature,
    this.weatherDescription,
    this.humidity,
    this.windSpeed,
    this.aqi,
  });
}

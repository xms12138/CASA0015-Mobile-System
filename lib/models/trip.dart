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

  // Main-table columns only; sub-lists are persisted by DatabaseService
  // into their own tables linked by trip_id.
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'start_time': startTime.millisecondsSinceEpoch,
    'end_time': endTime?.millisecondsSinceEpoch,
  };

  factory Trip.fromMap(
    Map<String, dynamic> map, {
    List<TrackPoint> trackPoints = const [],
    List<PhotoMarker> photos = const [],
    List<WeatherRecord> weatherRecords = const [],
  }) {
    return Trip(
      id: map['id'] as String,
      title: map['title'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      trackPoints: trackPoints,
      photos: photos,
      weatherRecords: weatherRecords,
    );
  }
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

  Map<String, dynamic> toMap(String tripId) => {
    'trip_id': tripId,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed': speed,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory TrackPoint.fromMap(Map<String, dynamic> map) {
    return TrackPoint(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
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

  Map<String, dynamic> toMap(String tripId) => {
    'id': id,
    'trip_id': tripId,
    'local_path': localPath,
    'remote_url': remoteUrl,
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory PhotoMarker.fromMap(Map<String, dynamic> map) {
    return PhotoMarker(
      id: map['id'] as String,
      localPath: map['local_path'] as String,
      remoteUrl: map['remote_url'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
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

  // Phase 6 will wire WeatherRecord persistence; toMap kept ready for use.
  Map<String, dynamic> toMap(String tripId) => {
    'trip_id': tripId,
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'temperature': temperature,
    'weather_description': weatherDescription,
    'humidity': humidity,
    'wind_speed': windSpeed,
    'aqi': aqi,
  };

  factory WeatherRecord.fromMap(Map<String, dynamic> map) {
    return WeatherRecord(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      temperature: (map['temperature'] as num?)?.toDouble(),
      weatherDescription: map['weather_description'] as String?,
      humidity: (map['humidity'] as num?)?.toDouble(),
      windSpeed: (map['wind_speed'] as num?)?.toDouble(),
      aqi: map['aqi'] as int?,
    );
  }
}

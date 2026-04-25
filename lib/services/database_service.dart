import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/trip.dart';
import 'firebase_service.dart';

// Aggregated stats for the home page. Computed in a single sweep so
// the home page doesn't need to hydrate every trip's sub-tables.
class TripStats {
  final int tripCount;
  final int photoCount;
  final double totalMeters;

  const TripStats({
    required this.tripCount,
    required this.photoCount,
    required this.totalMeters,
  });

  const TripStats.empty()
    : tripCount = 0,
      photoCount = 0,
      totalMeters = 0;
}

// Local SQLite persistence for trips and their sub-entities
// (track points, photos). Phase 5 scope: trip CRUD without weather.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const String _dbName = 'traveltrace.db';
  // v2 adds weather_records for Phase 6 (Connected Environments API).
  static const int _dbVersion = 2;

  Database? _db;

  // Bumped whenever the trips set changes (save/delete). History page
  // listens to this so it reloads after a stop-recording even though
  // IndexedStack keeps its State alive across tab switches.
  final ValueNotifier<int> tripsRevision = ValueNotifier<int>(0);

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _db = await _open();
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: add weather_records. Additive — preserves existing trips.
    if (oldVersion < 2) {
      await db.execute(_weatherTableSql);
      await db.execute(_weatherIndexSql);
    }
  }

  static const String _weatherTableSql = '''
    CREATE TABLE weather_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      trip_id TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      timestamp INTEGER NOT NULL,
      temperature REAL,
      weather_description TEXT,
      humidity REAL,
      wind_speed REAL,
      aqi INTEGER,
      FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
    )
  ''';

  static const String _weatherIndexSql =
      'CREATE INDEX idx_weather_trip ON weather_records(trip_id)';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        speed REAL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_track_points_trip ON track_points(trip_id)',
    );

    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_url TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_photos_trip ON photos(trip_id)');

    await db.execute(_weatherTableSql);
    await db.execute(_weatherIndexSql);
  }

  // Persist a completed trip and all its child rows atomically. Uses a
  // batch for bulk inserts — on busy devices this is meaningfully faster
  // than looping insert() calls, especially for trips with 100+ points.
  Future<void> saveTrip(Trip trip) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'trips',
        trip.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final batch = txn.batch();
      for (final point in trip.trackPoints) {
        batch.insert('track_points', point.toMap(trip.id));
      }
      for (final photo in trip.photos) {
        batch.insert(
          'photos',
          photo.toMap(trip.id),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final weather in trip.weatherRecords) {
        batch.insert('weather_records', weather.toMap(trip.id));
      }
      await batch.commit(noResult: true);
    });
    tripsRevision.value++;
    // Mirror to Firestore in the background. Failure is logged inside
    // FirebaseService — local persistence is the source of truth.
    unawaited(FirebaseService.instance.syncTrip(trip));
  }

  // List view: only the trips table, newest first. Sub-lists are left
  // empty — callers that need the full detail should use loadTripDetail.
  Future<List<Trip>> loadTrips() async {
    final db = await database;
    final rows = await db.query('trips', orderBy: 'start_time DESC');
    return rows.map(Trip.fromMap).toList();
  }

  Future<Trip?> loadTripDetail(String id) async {
    final db = await database;
    final tripRows = await db.query(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (tripRows.isEmpty) return null;

    final pointRows = await db.query(
      'track_points',
      where: 'trip_id = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );
    final photoRows = await db.query(
      'photos',
      where: 'trip_id = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );
    final weatherRows = await db.query(
      'weather_records',
      where: 'trip_id = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );

    return Trip.fromMap(
      tripRows.first,
      trackPoints: pointRows.map(TrackPoint.fromMap).toList(),
      photos: photoRows.map(PhotoMarker.fromMap).toList(),
      weatherRecords: weatherRows.map(WeatherRecord.fromMap).toList(),
    );
  }

  // Home page summary: trip count, photo count and total distance.
  // Distance is computed in Dart from track_points sorted by trip + time,
  // walking consecutive points with Geolocator.distanceBetween. A trip's
  // first point and the next trip's first point aren't connected because
  // we group rows by trip_id as we iterate.
  Future<TripStats> loadStats() async {
    final db = await database;
    final tripCountRow = await db.rawQuery('SELECT COUNT(*) AS c FROM trips');
    final photoCountRow = await db.rawQuery('SELECT COUNT(*) AS c FROM photos');
    final pointRows = await db.query(
      'track_points',
      columns: ['trip_id', 'latitude', 'longitude'],
      orderBy: 'trip_id ASC, timestamp ASC',
    );

    double totalMeters = 0;
    String? currentTripId;
    double? prevLat;
    double? prevLng;
    for (final row in pointRows) {
      final tripId = row['trip_id'] as String;
      final lat = (row['latitude'] as num).toDouble();
      final lng = (row['longitude'] as num).toDouble();
      if (tripId != currentTripId) {
        currentTripId = tripId;
        prevLat = lat;
        prevLng = lng;
        continue;
      }
      totalMeters += Geolocator.distanceBetween(
        prevLat!,
        prevLng!,
        lat,
        lng,
      );
      prevLat = lat;
      prevLng = lng;
    }

    return TripStats(
      tripCount: (tripCountRow.first['c'] as int?) ?? 0,
      photoCount: (photoCountRow.first['c'] as int?) ?? 0,
      totalMeters: totalMeters,
    );
  }

  // ON DELETE CASCADE in schema cleans up children automatically.
  Future<void> deleteTrip(String id) async {
    final db = await database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
    tripsRevision.value++;
    unawaited(FirebaseService.instance.deleteTripFromCloud(id));
  }
}

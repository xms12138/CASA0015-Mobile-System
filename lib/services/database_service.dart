import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/trip.dart';

// Local SQLite persistence for trips and their sub-entities
// (track points, photos). Phase 5 scope: trip CRUD without weather.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const String _dbName = 'traveltrace.db';
  static const int _dbVersion = 1;

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
    );
  }

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
      await batch.commit(noResult: true);
    });
    tripsRevision.value++;
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

    return Trip.fromMap(
      tripRows.first,
      trackPoints: pointRows.map(TrackPoint.fromMap).toList(),
      photos: photoRows.map(PhotoMarker.fromMap).toList(),
    );
  }

  // ON DELETE CASCADE in schema cleans up children automatically.
  Future<void> deleteTrip(String id) async {
    final db = await database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
    tripsRevision.value++;
  }
}

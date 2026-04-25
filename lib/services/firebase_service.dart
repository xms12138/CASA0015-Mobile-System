import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/trip.dart';

// Cloud-sync layer backed by Firebase Anonymous Auth + Firestore.
// Storage is intentionally not used — photos stay local (the free-tier
// Storage bucket requires a paid billing plan, which the course rubric
// doesn't require). Only trip metadata (route / photos / weather) is
// mirrored to the cloud so the user can browse their history on another
// device and so we satisfy the "external cloud service" requirement.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get uid => _auth.currentUser?.uid;

  // Guarantee a signed-in user before any Firestore write. Idempotent —
  // repeat calls short-circuit once a user exists.
  Future<String?> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;
    try {
      final credential = await _auth.signInAnonymously();
      final id = credential.user?.uid;
      debugPrint('FirebaseService signed in anonymously: $id');
      return id;
    } catch (e) {
      debugPrint('FirebaseService sign-in failed: $e');
      return null;
    }
  }

  // Mirror a trip and all its sub-collections to Firestore under
  // users/{uid}/trips/{tripId}. Fire-and-forget from the caller's POV:
  // any failure is logged and swallowed so local persistence isn't
  // blocked by network issues.
  Future<void> syncTrip(Trip trip) async {
    final id = await ensureSignedIn();
    if (id == null) return;

    try {
      final tripDoc =
          _firestore.collection('users').doc(id).collection('trips').doc(trip.id);

      await tripDoc.set({
        'title': trip.title,
        'start_time': trip.startTime.millisecondsSinceEpoch,
        'end_time': trip.endTime?.millisecondsSinceEpoch,
        'point_count': trip.trackPoints.length,
        'photo_count': trip.photos.length,
        'weather_count': trip.weatherRecords.length,
        'synced_at': FieldValue.serverTimestamp(),
      });

      // Track points can run into the hundreds; one Firestore batch caps at
      // 500 operations, so commit in chunks of 400.
      const chunkSize = 400;
      for (var offset = 0; offset < trip.trackPoints.length; offset += chunkSize) {
        final batch = _firestore.batch();
        final end = (offset + chunkSize).clamp(0, trip.trackPoints.length);
        for (var i = offset; i < end; i++) {
          final p = trip.trackPoints[i];
          final ref = tripDoc.collection('track_points').doc('$i');
          batch.set(ref, {
            'index': i,
            'latitude': p.latitude,
            'longitude': p.longitude,
            'altitude': p.altitude,
            'speed': p.speed,
            'timestamp': p.timestamp.millisecondsSinceEpoch,
          });
        }
        await batch.commit();
      }

      if (trip.photos.isNotEmpty || trip.weatherRecords.isNotEmpty) {
        final batch = _firestore.batch();
        for (final photo in trip.photos) {
          batch.set(tripDoc.collection('photos').doc(photo.id), {
            'local_path': photo.localPath,
            'remote_url': photo.remoteUrl,
            'latitude': photo.latitude,
            'longitude': photo.longitude,
            'timestamp': photo.timestamp.millisecondsSinceEpoch,
          });
        }
        for (var i = 0; i < trip.weatherRecords.length; i++) {
          final w = trip.weatherRecords[i];
          batch.set(tripDoc.collection('weather_records').doc('$i'), {
            'latitude': w.latitude,
            'longitude': w.longitude,
            'timestamp': w.timestamp.millisecondsSinceEpoch,
            'temperature': w.temperature,
            'weather_description': w.weatherDescription,
            'humidity': w.humidity,
            'wind_speed': w.windSpeed,
            'aqi': w.aqi,
          });
        }
        await batch.commit();
      }

      debugPrint('FirebaseService synced trip ${trip.id}');
    } catch (e) {
      debugPrint('FirebaseService syncTrip failed: $e');
    }
  }

  Future<void> deleteTripFromCloud(String tripId) async {
    final id = await ensureSignedIn();
    if (id == null) return;
    try {
      final tripDoc =
          _firestore.collection('users').doc(id).collection('trips').doc(tripId);
      // Firestore doesn't cascade — delete subcollections first. For a
      // typical trip (a few hundred points, handful of photos) this is
      // fast enough inline.
      for (final sub in ['track_points', 'photos', 'weather_records']) {
        final snapshot = await tripDoc.collection(sub).get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      }
      await tripDoc.delete();
      debugPrint('FirebaseService deleted trip $tripId');
    } catch (e) {
      debugPrint('FirebaseService deleteTripFromCloud failed: $e');
    }
  }
}

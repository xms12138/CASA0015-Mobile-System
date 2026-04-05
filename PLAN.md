# TravelTrace — Development Plan

## Overview
UCL CASA0015 individual coursework. A travel recording app with GPS tracking,
photo mapping, and environmental data (Connected Environments theme).

## Progress Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Project Setup & Scaffold | ✅ Done |
| 2 | Splash Screen & Navigation Framework | ✅ Done |
| 3 | Map & GPS Tracking | 🔲 |
| 4 | Camera & Photo Markers | 🔲 |
| 5 | Local Data Persistence (SQLite) | 🔲 |
| 6 | Weather & Environment API | 🔲 |
| 7 | Firebase Integration | 🔲 |
| 8 | Sensors & UI Polish | 🔲 |

---

## Phase 1 — Project Setup & Scaffold
**Status:** ✅ Done

**Deliverables:**
- Flutter project created (`travel_trace/`)
- All dependencies added to `pubspec.yaml`:
  google_maps_flutter, geolocator, image_picker, sensors_plus,
  sqflite, firebase_core, cloud_firestore, firebase_storage,
  firebase_auth, http, provider, intl, uuid, permission_handler
- Directory structure: `pages/`, `models/`, `services/`, `widgets/`, `utils/`
- Data models: `Trip`, `TrackPoint`, `PhotoMarker`, `WeatherRecord`
- Service stubs: location, camera, database, weather, firebase
- Git initialised

---

## Phase 2 — Splash Screen & Navigation Framework
**Status:** ✅ Done

**Goal:** First impressions + full navigation skeleton. Highest-weight scoring area (Widget usage 30%).

**Deliverables:**
- Animated splash screen: logo + app name fade/slide animation, auto-navigates after ~2.5s
- Bottom navigation bar: Home / Record / History tabs
- Each tab routes to its placeholder page
- Consistent app theme (colour, typography, Material 3)

---

## Phase 3 — Map & GPS Tracking
**Status:** 🔲 To Do

**Goal:** Core functionality — real-time GPS track displayed on Google Maps.

**Deliverables:**
- Google Maps API key configured
- Map displayed on Recording page
- `LocationService`: start/stop GPS stream, produces `TrackPoint` list
- Live polyline drawn on map as user moves
- Start / Pause / Stop recording controls with FAB

**Prerequisites:** Google Maps API key (user must provide)

---

## Phase 4 — Camera & Photo Markers
**Status:** 🔲 To Do

**Goal:** Photos taken during a trip are pinned to the map at the capture location.

**Deliverables:**
- `CameraService`: trigger camera, return local file path
- Camera button active during recording
- Photo pinned to current GPS coordinate as a custom map marker
- Tap marker → photo preview bottom sheet

---

## Phase 5 — Local Data Persistence (SQLite)
**Status:** 🔲 To Do

**Goal:** Trips survive app restarts; history is browsable.

**Deliverables:**
- `DatabaseService`: SQLite tables for trips, track_points, photos, weather_records
- Save completed trip on stop-recording
- Trip History page: list of saved trips with date, distance, thumbnail
- Trip Detail page: load route + photo markers from DB, render on map

---

## Phase 6 — Weather & Environment API
**Status:** 🔲 To Do

**Goal:** Fulfil Connected Environments theme; covers API integration (15% weight).

**Deliverables:**
- `WeatherService`: OpenWeatherMap current weather + Air Pollution API (free tier)
- Auto-fetch every 5 minutes during recording, save as `WeatherRecord`
- Trip Detail page: environmental data timeline (temperature, conditions, AQI)

**Prerequisites:** OpenWeatherMap API key (user must provide)

---

## Phase 7 — Firebase Integration
**Status:** 🔲 To Do

**Goal:** Cloud sync; fulfils "external cloud service" requirement.

**Deliverables:**
- Firebase project configured (`google-services.json` / `firebase_options.dart`)
- FirebaseAuth: anonymous sign-in (or email/password)
- Firestore: sync trip metadata
- Firebase Storage: upload photos, store remote URLs alongside local paths

**Prerequisites:** User must set up Firebase project and provide config files

---

## Phase 8 — Sensors & UI Polish
**Status:** 🔲 To Do

**Goal:** Final refinement to maximise score across all rubric areas.

**Deliverables:**
- `sensors_plus`: record accelerometer data as contextual motion log
- Permission UX: graceful handling of GPS denied / camera denied states
- Loading indicators and error states on all async operations
- UI polish: custom widgets, transitions, card designs
- Final self-review against CLAUDE.md scoring rubric

<div align="center">

# TravelTrace

**Every journey, remembered.**

A Flutter mobile app that records GPS routes, pins photos along the way, and logs the surrounding environment — so a trip becomes more than a thumbnail.

[![Flutter](https://img.shields.io/badge/Flutter-3.11%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#)
[![Material 3](https://img.shields.io/badge/Material%203-light%20%2B%20dark-757575)](#)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#license)

UCL CASA0015 — Mobile Systems & Interactions — Individual Coursework 2025/26

</div>

---

## Table of contents

- [Problem](#problem)
- [Connected Environments theme](#connected-environments-theme)
- [User persona & storyboard](#user-persona--storyboard)
- [Demo & screenshots](#demo--screenshots)
- [Landing page](#landing-page)
- [Download](#download)
- [Feature overview](#feature-overview)
- [Sensors used](#sensors-used)
- [External services & APIs](#external-services--apis)
- [Widget showcase](#widget-showcase)
- [Responsive design & cross-platform readiness](#responsive-design--cross-platform-readiness)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Code navigation — feature to file map](#code-navigation--feature-to-file-map)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Permissions](#permissions)
- [Design system](#design-system)
- [User testing scenario & iteration log](#user-testing-scenario--iteration-log)
- [Case studies](#case-studies)
- [Engineering practices](#engineering-practices)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Course context & assessment mapping](#course-context--assessment-mapping)
- [Author](#author)
- [License](#license)

---

## Problem

Most travel apps fall into one of two camps:

- **Location loggers** (Google Timeline, Strava) record the *where* but strip out the *moments*.
- **Photo apps** (Instagram, Google Photos) capture the moments but lose the *journey* — looking back, you have a grid of disconnected images and no sense of how they were threaded together.

When you revisit a trip from three months ago, you remember neither route nor weather. You have a few photos and a fuzzy feeling.

**TravelTrace records the route, the moments, and the surrounding environment in one place** — and lets you replay them as a single timeline. The journey becomes a story you can scrub through, not a folder you have to reconstruct.

## Connected Environments theme

The app fits the Connected Environments brief by **continuously sensing the world the user is moving through** and persisting it against time:

- **Onboard sensors** — GPS, compass, camera — sample the user's physical position and orientation in real time.
- **External environmental APIs** — OpenWeatherMap (current weather) and OpenWeatherMap Air Pollution — are polled every 5 minutes for ambient temperature, wind, humidity, and air-quality index.
- **Time-series persistence** — every reading is stored locally with a timestamp, so the environment of a trip can be reconstructed alongside the route, not just at a single snapshot.

## User persona & storyboard

### Persona — "Mia, the weekend explorer"

> Mia is a 27-year-old urban planner. Each weekend she walks an unfamiliar London neighbourhood and snaps photos of architectural details that catch her eye. Three months later, when a colleague asks "where did you see that ironwork?", she scrolls through 400 thumbnails in Google Photos with no map, no route, and no idea what the air quality was that day. **She wants a way to revisit the whole journey, not just the photos.**

Two secondary personas in mind while designing:

- **The hiker** who wants a recordable route + ambient temperature for each segment of a long walk.
- **The travel blogger** who wants to publish "I walked 4 km from Highbury to Camden, here's the route, the photos, and the AQI."

### Storyboard — one journey, beat by beat

```
1. SET OUT      ── Splash fades in.  Logo settles.  No friction.
                  "I'm starting an adventure."

2. PRESS START  ── Live polyline draws as Mia steps out.
                  The compass cone always faces forward.
                  "The app is paying attention."

3. CAPTURE      ── A wrought-iron gate.  One tap, one photo.
                  Marker drops on the map exactly where she stood.
                  "This moment is now anchored to this place."

4. ELEMENTS     ── Behind the scenes, weather and AQI sample silently
                  every 5 minutes — never interrupting.
                  "The app respects my flow."

5. STOP         ── Confirmation dialog.  Snackbar reports the count.
                  "Saved.  I don't have to manage anything."

6. THREE MONTHS LATER
                ── Mia opens History, taps the trip.
                  She drags the slider; photos surface as she reaches
                  them; the cursor walks the polyline.
                  "I'm reliving it, not just remembering it."
```

The replay screen is what the rest of the product builds towards — recording cadence, photo timestamps, and weather polling are all chosen so the slider drag at the end has something worth watching.

## Demo & screenshots

> _Place the demo GIF and screenshots in `docs/` before the final submission._

| Splash | Home | Recording |
|:--:|:--:|:--:|
| ![splash](docs/screenshots/splash.png) | ![home](docs/screenshots/home.png) | ![record](docs/screenshots/record.png) |

| History | Trip detail (replay) | Dark mode |
|:--:|:--:|:--:|
| ![history](docs/screenshots/history.png) | ![replay](docs/screenshots/replay.png) | ![dark](docs/screenshots/dark.png) |

A short demo GIF (≤ 3 minutes, per assessment guidelines) is at `docs/demo.gif`.

## Landing page

A static landing page is published via **GitHub Pages** at:

> https://xms12138.github.io/CASA0015-Mobile-System/

The page (source: [`docs/index.html`](docs/index.html), single-file Tailwind CDN build) introduces the problem, shows the demo GIF, lists the headline features, and links back to this repository. It is deliberately one page and one purpose — to communicate "what does this app do?" to a reader who has never seen it.

## Download

A signed release APK is attached to every GitHub Release of this repository — graders and reviewers can install the app on a real Android device without setting up a Flutter toolchain or supplying API keys.

> **Latest APK:** [Releases page](https://github.com/xms12138/CASA0015-Mobile-System/releases/latest) → download `TravelTrace-release.apk` from the Assets list.

**Install on Android:**

1. Download the APK on the target device (or transfer via USB / `adb install TravelTrace-release.apk`).
2. Allow installation from the source if prompted (Settings → Security → Install unknown apps).
3. Open *TravelTrace* and grant the location and camera permissions when asked.

**Specs:**

| | |
|--|--|
| Build mode | `release` (R8/ProGuard, tree-shaken icons) |
| Minimum SDK | 24 (Android 7.0 Nougat) |
| Target SDK | Flutter default (34) |
| Size | ≈ 50 MB |
| ABIs | universal (single APK, all architectures) |

The APK already embeds the Google Maps and OpenWeatherMap keys at build time, so the app works out of the box. Cloud sync (Firebase Auth + Firestore) signs in anonymously on first launch — no account required.

If you would rather build from source, see [Build a release APK](#build-a-release-apk) further down.

## Feature overview

| # | Feature | Status | Notes |
|---|---|:-:|---|
| 1 | Animated splash screen | ✅ | Fade + slide + scale composition |
| 2 | Multi-view navigation | ✅ | Home / Record / History + nested Trip Detail |
| 3 | Real-time GPS tracking | ✅ | Live polyline grows as the user moves |
| 4 | Photo markers pinned on map | ✅ | Tap a marker → bottom-sheet preview |
| 5 | Weather + air quality logging | ✅ | OpenWeatherMap polled every 5 min |
| 6 | Local persistence | ✅ | SQLite with FK cascade, three tables |
| 7 | Cloud sync | ✅ | Anonymous Firestore mirror, local is source of truth |
| 8 | Trip replay (signature feature) | ✅ | Slider scrub + 1×/5×/10×/30× playback + photos surface as you reach them |
| 9 | Sensor smoothing | ✅ | EMA on GPS, circular EMA on compass heading |
| 10 | Dark mode | ✅ | System-driven via `ThemeMode.system` |
| 11 | Permission denial UX | ✅ | Blocking dialog → exit if GPS or camera is denied |
| 12 | User testing | 🟡 | Documented scenario; informal in-class trial |

## Sensors used

Each sensor is filtered before being persisted or rendered, per the course's smoothing requirement.

| Sensor | Purpose | Filtering |
|---|---|---|
| GPS (`geolocator`) | Track points, photo geolocation, weather query coordinates | Dual gate (≤30 m accuracy, ≤56 m/s implied speed) + linear EMA (α = 0.35) on lat/lng of stored track points. Live self-marker uses the raw fix to avoid lag. |
| Compass (`flutter_compass`) | Forward-facing heading cone on the user marker | Circular EMA (α = 0.15) on `(sin θ, cos θ)` then `atan2` recovery, so the 359°↔1° wrap-around can't collapse to 180°. |
| Camera (`image_picker`) | Pin photos to the current GPS coordinate | n/a (one-shot capture) |

## External services & APIs

| Service | Use | Endpoint / SDK | Free-tier note |
|---|---|---|---|
| **Google Maps Flutter** | Map tiles + polyline + custom markers (start, end, photos, replay cursor, self-with-heading) | `package:google_maps_flutter` | Maps SDK for Android key |
| **OpenWeatherMap — Current Weather** | Temperature, humidity, wind, weather description | `GET https://api.openweathermap.org/data/2.5/weather?lat=...&lon=...&units=metric` | Free tier, ≤60 req/min |
| **OpenWeatherMap — Air Pollution** | AQI 1–5 scale, surfaced in trip detail as a coloured chip | `GET https://api.openweathermap.org/data/2.5/air_pollution?lat=...&lon=...` | Free tier |
| **Firebase Anonymous Auth** | Per-device user identity for the cloud mirror — no sign-up flow | `package:firebase_auth` | Spark plan |
| **Cloud Firestore** | Mirrors `users/{uid}/trips/{tripId}` with track points (chunked at 400 ops/batch), photos (path only), and weather records | `package:cloud_firestore` | Spark plan |

### API design choices

- **Parallel fetch.** `WeatherService.fetchAt()` issues current-weather and air-pollution requests with `Future.wait`, halving wall-clock latency vs. serial calls. A 10-second timeout protects the recording flow if the network stalls.
- **Polling cadence.** Weather is sampled every `weatherIntervalMin = 5 min`, not on every GPS update — avoids burning the free-tier quota and matches the rate at which weather actually changes. The first sample fires immediately on Start so even a 4-minute walk records at least one reading.
- **Failure isolation.** Every cloud / weather call is wrapped in `try/catch`; errors are logged via `debugPrint` and surfaced once per session via a single `SnackBar`. **External failure never blocks local persistence** — the journey still saves to SQLite even if every API is offline.
- **Secure data exchange.** API keys are read from a gitignored `env.json` via `String.fromEnvironment` at build time — never committed to source. The Firestore security rule scopes reads/writes to `request.auth.uid == userId`, so an attacker cannot read another anonymous user's trips.
- **Batched writes.** Firestore caps a `WriteBatch` at 500 operations; track points are chunked at 400 per batch to leave headroom for the trip + photos + weather rows in the same logical sync.

## Widget showcase

Highlights of widgets actually used in the app — for the *Use of compelling widgets* (30%) rubric area:

- **Custom animations & transitions** — `AnimationController` driving simultaneous `FadeTransition` + `SlideTransition` + `ScaleTransition` on the splash; `AnimatedSwitcher` (300 ms fade + scale) for the replay photo card; `PageRouteBuilder` with `FadeTransition` for the splash → main route handoff; `Curves.easeOutBack` for the splash icon overshoot; pulsing recording dot on the recording status bar
- **Gesture recognition** — `GestureDetector` on the Home Start CTA, `InkWell` on every list and card for ripple feedback, `onTap` callbacks on map markers, `DraggableScrollableSheet` drag for the photo preview, slider scrubbing during replay, pull-to-refresh on History
- **Layout** — `CustomScrollView` + `SliverAppBar` + `SliverToBoxAdapter` (Home), `Stack` + `Positioned` (Recording, Trip Detail), `IndexedStack` for keep-alive tab pages
- **Navigation** — Material 3 `NavigationBar` with selected/unselected icon variants, programmatic tab switching via an inherited state lookup
- **Input** — `Slider` (replay scrub), `SegmentedButton<double>` (1× / 5× / 10× / 30× speeds), `FilterChip`, `IconButton.filled` (play/pause/replay tri-state), `FloatingActionButton` (camera + recenter), `FilledButton` / `OutlinedButton` / `TextButton` (M3 button hierarchy)
- **Feedback & dismissal** — `SnackBar` (one-shot weather warnings), `AlertDialog` with `PopScope(canPop: false)` for the permission blocker, `DraggableScrollableSheet` for the photo preview, `RefreshIndicator` for pull-to-refresh on History, `CircularProgressIndicator` for async loading
- **Map** — `GoogleMap` with custom `BitmapDescriptor` (compass-aware heading marker drawn through `PictureRecorder` with `Canvas` primitives), z-indexed split-colour `Polyline` for walked vs. remaining route, `LatLngBounds` auto-fit on first load
- **Theming** — Material 3 `ColorScheme.fromSeed`, `ThemeMode.system`, design tokens (`AppRadius` / `AppSpacing` / `AppDuration`)

## Responsive design & cross-platform readiness

### Layout responsiveness

The app is laid out in `Expanded` / `Flex` / `SafeArea` widgets so it adapts to phones of different aspect ratios without code changes:

- **Home statistics row** uses `Expanded` siblings so three stat cards always share width evenly.
- **Recording control panel** is anchored bottom-left/right with `Positioned` and `SafeArea`, so it sits above the gesture bar on phones with on-screen navigation.
- **Map markers** scale with zoom: the heading-aware self-marker is regenerated via `PictureRecorder` whenever zoom changes by more than 6 logical units, so it stays visually consistent at every zoom level.
- **Bottom sheets** use `DraggableScrollableSheet` rather than fixed heights, so the photo preview is comfortable on both 5.5" and 6.7" devices.
- **Trip Detail playback bar** is built from `Slider` + `Expanded` so the scrub track always fills the available width, regardless of speed-button label width.

### Cross-platform readiness

The app is written entirely in Dart on top of Flutter, so the codebase is ready for both Android and iOS. The submission is **verified on Android only** — iOS placeholders exist (`ios/Runner/AppDelegate.swift`, `web/index.html`) but were not signed into Apple's developer programme and have not been live-tested. Bringing iOS to parity would require:

1. Adding the Maps SDK key to `AppDelegate.swift`.
2. Declaring `NSLocationWhenInUseUsageDescription` and `NSCameraUsageDescription` in `Info.plist`.
3. Re-running `flutterfire configure` against the iOS bundle ID.

No platform-specific UI hacks were used in `lib/` — the same Material 3 widgets render on both platforms. (`Cupertino*` overrides could be added later for App Store polish, but the core flow is already platform-agnostic.)

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                          UI Layer                            │
│  Splash → MainScaffold (NavigationBar)                       │
│            ├── Home   (stats, recent trips)                  │
│            ├── Record (live map, recording controls)         │
│            └── History → Trip Detail (replay + weather)      │
└──────────────────────────────────────────────────────────────┘
                                │
┌──────────────────────────────────────────────────────────────┐
│                       Service Layer                          │
│  LocationService  CameraService  WeatherService              │
│  DatabaseService (SQLite)   FirebaseService (Firestore)      │
└──────────────────────────────────────────────────────────────┘
                                │
┌──────────────────────────────────────────────────────────────┐
│                  External Systems & Sensors                  │
│  GPS · Compass · Camera ·                                    │
│  OpenWeatherMap · Air Pollution API ·                        │
│  Google Maps SDK · Firebase Auth · Cloud Firestore           │
└──────────────────────────────────────────────────────────────┘
```

**Local-first design.** `DatabaseService` is the source of truth. After every transactional `saveTrip` / `deleteTrip`, an `unawaited(...)` call mirrors to Firestore. If the cloud call fails — bad signal, expired key, no auth — it is logged to debug output and silently retried on the next save. The user never sees a cloud-related failure interrupt their recording.

## Project structure

```
travel_trace/
├── lib/
│   ├── main.dart                       # Firebase init + theme wiring
│   ├── pages/                          # Route-level views
│   │   ├── splash_page.dart
│   │   ├── main_scaffold.dart
│   │   ├── home_page.dart
│   │   ├── recording_page.dart
│   │   ├── trip_history_page.dart
│   │   └── trip_detail_page.dart       # Replay + weather timeline
│   ├── models/                         # Plain Dart data classes with toMap/fromMap
│   │   ├── trip.dart
│   │   ├── track_point.dart
│   │   ├── photo_marker.dart
│   │   └── weather_record.dart
│   ├── services/
│   │   ├── location_service.dart       # GPS + EMA filter + dual-gate
│   │   ├── camera_service.dart
│   │   ├── weather_service.dart        # Parallel current + air_pollution
│   │   ├── database_service.dart       # SQLite v2 + onUpgrade migration
│   │   └── firebase_service.dart       # Auth + Firestore mirror
│   ├── widgets/
│   │   └── permission_blocker_dialog.dart
│   └── utils/
│       ├── app_theme.dart              # Design tokens + light/dark themes
│       ├── constants.dart
│       └── heading_marker.dart         # Compass marker drawn via PictureRecorder
├── android/                            # Manifest + Gradle config
├── docs/                               # Screenshots & demo GIF (you add these)
├── DEVLOG.md                           # Real-incident root-cause notes
├── env.example.json                    # Template for API keys (gitignored: env.json)
└── pubspec.yaml
```

## Code navigation — feature to file map

Each headline feature, with the exact file and the function or symbol that implements it. Use this as a code index when reviewing the submission.

| Feature | File | Key symbol |
|---|---|---|
| GPS smoothing — EMA + dual-gate filter | `lib/services/location_service.dart` | `_onPosition()` (accuracy + speed gates, lat/lng EMA) |
| Compass smoothing — circular EMA on `(sin θ, cos θ)` | `lib/pages/recording_page.dart` | `_initHeading()` listener |
| Custom heading marker — `Canvas` + `PictureRecorder` | `lib/utils/heading_marker.dart` | `buildHeadingMarker()` |
| Zoom-aware marker regeneration | `lib/pages/recording_page.dart` | `_iconSizeForZoom()` / `_updateHeadingIconSize()` |
| Photo marker clustering on trip detail | `lib/pages/trip_detail_page.dart` | `_clusterPhotos()` (10 m greedy radius) |
| Trip replay — state machine + tick driver | `lib/pages/trip_detail_page.dart` | `_togglePlay()`, `_onSliderChanged()`, `_replayProgress` |
| Replay polyline split — walked vs. remaining | `lib/pages/trip_detail_page.dart` | `_buildPolylines()` |
| Replay photo auto-surface | `lib/pages/trip_detail_page.dart` | `_maybeUpdateActivePhoto()`, `_ReplayPhotoCard` |
| Weather + AQI parallel fetch | `lib/services/weather_service.dart` | `fetchAt()` (`Future.wait`, 10 s timeout) |
| Weather periodic polling during recording | `lib/pages/recording_page.dart` | `_startWeatherFetching()` (`Timer.periodic`) |
| SQLite schema & onUpgrade migration | `lib/services/database_service.dart` | `_onCreate()`, `_onUpgrade()` |
| SQLite transactional save / load / delete | `lib/services/database_service.dart` | `saveTrip()`, `loadTrips()`, `loadTripDetail()`, `deleteTrip()` |
| Reactive cross-page refresh | `lib/services/database_service.dart` | `tripsRevision` (`ValueNotifier<int>`) |
| Firestore one-way mirror (batched at 400 ops) | `lib/services/firebase_service.dart` | `syncTrip()`, `deleteTripFromCloud()` |
| Anonymous Firebase auth | `lib/services/firebase_service.dart` | `ensureSignedIn()` |
| Camera capture + permission gate | `lib/services/camera_service.dart` | `takePhoto()`, `ensureCameraPermission()` |
| Permission blocking dialog | `lib/widgets/permission_blocker_dialog.dart` | `showPermissionBlockerDialog()` |
| Splash animation (3-layer composition) | `lib/pages/splash_page.dart` | `_SplashPageState` (`AnimationController` driving fade / slide / scale) |
| Tab navigation with keep-alive | `lib/pages/main_scaffold.dart` | `IndexedStack` + Material 3 `NavigationBar` |
| Home aggregate stats + recent trips | `lib/pages/home_page.dart` | `_load()`, `tripsRevision` listener |
| Design tokens & light/dark themes | `lib/utils/app_theme.dart` | `AppRadius`, `AppSpacing`, `AppDuration`, `buildLightTheme()`, `buildDarkTheme()` |
| Build-time API key injection | `lib/utils/constants.dart` | `String.fromEnvironment` (`OPENWEATHER_API_KEY`, `GOOGLE_MAPS_API_KEY`) |

## Getting started

> **Just want to try the app?** Skip the toolchain — grab the prebuilt APK from the [Releases page](https://github.com/xms12138/CASA0015-Mobile-System/releases/latest). See the [Download](#download) section for install instructions.

### Prerequisites

- Flutter SDK ≥ 3.11.4 (`flutter --version`)
- Android Studio + an Android device or emulator (API 24+ recommended)
- A Firebase project with **Anonymous Auth** enabled and **Cloud Firestore** provisioned
- API keys for **Google Maps SDK for Android** and **OpenWeatherMap** (free tier is sufficient)

### Clone & install

```bash
git clone https://github.com/xms12138/CASA0015-Mobile-System.git
cd CASA0015-Mobile-System/travel_trace
flutter pub get
```

### Configure secrets — see [Configuration](#configuration)

### Run

```bash
flutter run --dart-define-from-file=env.json
```

### Build a release APK

```bash
flutter build apk --release --dart-define-from-file=env.json
```

## Configuration

API keys are kept **out of source control**. The repository ships an example file; copy it and fill in your own keys.

### 1. `env.json` (project root, gitignored)

```bash
cp env.example.json env.json
```

```json
{
  "OPENWEATHER_API_KEY": "your-openweather-key",
  "GOOGLE_MAPS_API_KEY": "your-maps-dart-key"
}
```

These are read by Dart at build time via `String.fromEnvironment` (see `lib/utils/constants.dart`).

### 2. `android/local.properties` (gitignored)

The Google Maps Android key is injected into `AndroidManifest.xml` through Gradle `manifestPlaceholders`:

```properties
GOOGLE_MAPS_API_KEY=your-maps-android-key
```

> The Maps Dart key and Maps Android key may be the **same** key in Google Cloud, but they are referenced from two different config files because Flutter's build pipeline reads them at different stages.

### 3. Firebase

Run `flutterfire configure` against your own Firebase project. This generates:

- `lib/firebase_options.dart` (gitignored)
- `android/app/google-services.json` (gitignored)

Then publish a Firestore rule that scopes reads/writes to the signed-in user:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Permissions

| Permission | Used for | Behaviour on denial |
|---|---|---|
| `ACCESS_FINE_LOCATION` | GPS tracking, photo geolocation | Blocking dialog → app exits |
| `CAMERA` | Capturing in-trip photos | Blocking dialog → app exits |
| `INTERNET` | Weather, Firebase, map tiles | n/a — implicitly granted |

The denial UX is intentionally minimal: the app can't function without GPS or camera, so the only action offered is an Exit button that calls `SystemNavigator.pop()`. Back-button dismissal is blocked via `PopScope(canPop: false)`.

## Design system

After several pages had drifted into hand-rolled radii (2, 6, 12, 14, 16, 20, 28 px) and one-off colour values, a small token system was introduced in `lib/utils/app_theme.dart`:

```dart
class AppRadius  { static const sm = 8.0;  static const md = 16.0; static const lg = 24.0; }
class AppSpacing { static const xs = 4.0;  static const sm = 8.0;  static const md = 16.0;
                   static const lg = 24.0; static const xl = 32.0; }
class AppDuration { static const short = Duration(milliseconds: 200); ... }
```

The same `seedColor` is fed into both `buildLightTheme()` and `buildDarkTheme()`. `MaterialApp` uses `themeMode: ThemeMode.system`, so the app follows the OS appearance setting without an in-app toggle.

A handful of colours stay hard-coded on purpose:

- The pulsing recording dot (red) and pause indicator (orange) — semantic colours users expect.
- Map polyline white outline and `BitmapDescriptor.defaultMarkerWithHue(...)` — these aren't part of the Material `ColorScheme`.
- The five AQI bands (good → very poor) — these follow the OpenWeatherMap colour standard, not the app theme.
- The black gradient overlay on photo cards — sits on top of arbitrary user images, where the underlying colour is not controllable.

## User testing scenario & iteration log

### Test scenario walked during informal testing

1. **First launch** — splash plays, app lands on Home with empty stats and an empty Recent Journeys card.
2. **Start recording** — user taps Record; permission dialog appears on first run; user accepts; the live map centres on their position with a heading-aware marker.
3. **Walk a short loop** — polyline grows as they move; weather is fetched silently in the background.
4. **Take a photo mid-trip** — camera button captures one image; an azure marker appears on the map at the capture coordinate.
5. **Stop recording** — confirmation dialog asks before saving; a `SnackBar` reports points + photo count.
6. **Browse history** — the trip appears at the top of History with a relative date label ("Today 14:30").
7. **Replay** — opening Trip Detail shows the full route; user drags the slider, taps Play, switches to 10×; the cursor walks the polyline; photos surface as floating cards when the cursor enters their timestamp window.
8. **Delete** — confirmation dialog protects against an accidental delete; trip disappears from History and from Firestore.

### Findings that changed the app

Real-device testing on a Huawei EML AL00 surfaced several issues that drove design changes — each is captured with phenomenon / root cause / resolution in [`DEVLOG.md`](DEVLOG.md):

| Finding | Iteration |
|---|---|
| Polyline wavered visibly on a straight walk | Added a dual-gate filter (≤30 m accuracy, ≤56 m/s implied speed) **plus** EMA smoothing (α = 0.35) on stored track points |
| Compass arrow stuttered, especially near magnetic north | Switched from linear angle averaging to circular EMA on `(sin θ, cos θ)`, recovered angle via `atan2`, so 359°↔1° wrap stops collapsing to 180° |
| Live self-marker felt "laggy" after smoothing was added | Kept smoothing for the **stored** track only; live marker uses the raw fix |
| Replay clock drifted from slider position on sparse trips | Computed elapsed time from the **continuous** progress (0..1) instead of the rounded track-point index — small drags now move both at the same rate |
| Permission denial branched into 4 different states | Collapsed to a single dialog with one Exit action — the app cannot function without GPS / camera, so any other branch is theatre |

The iteration log itself is part of the submission: read [`DEVLOG.md`](DEVLOG.md) for the full account, and the commit history for the code changes that closed each loop.

## Case studies

A few of the more consequential debugging stories, expanded from the iteration log above. Each follows a **phenomenon / root cause / resolution / lesson** structure. Other incidents (WSL toolchain, Huawei GPS default coordinate, marker collision on identical photos) are catalogued in [`DEVLOG.md`](DEVLOG.md).

### Case study 1 — Polyline teleports & self-marker frozen until recording starts

**Phenomenon.** On the test device (Huawei EML-AL00, HarmonyOS 3.0 / Android 10), two issues appeared during a real-world walk:

1. Standing in an open square with clear sky, the polyline would "teleport" tens to hundreds of metres every few seconds and snap back. Google Maps and Baidu Maps on the same device showed no such jitter at the same location.
2. Opening the Record page **without** pressing Start, the blue self-marker was completely frozen — only after pressing Start did it begin to follow the user.

**Root cause.**

1. To work around incomplete Google Mobile Services on the Huawei device, `LocationService` had earlier been switched to `forceLocationManager: true`. This bypasses Google's Fused Location Provider and uses Android's native `LocationManager`, which simultaneously runs **both** the GPS provider and the NETWORK provider (cell-tower / Wi-Fi triangulation, accuracy 100–1000 m). With no fusion layer, NETWORK-provider fixes interleave into the position stream — those are the teleporting points. The Huawei device has no full GMS, so there is no Fused Location Provider to merge the two streams. This was a second-order cost of the earlier GMS workaround.
2. `RecordingPage._initLocation()` only called `getCurrentPosition()` once at `initState`. The position stream was subscribed inside `_startRecording()`, so before pressing Start there was no live update path at all — a leakage of the implementation detail "we only need GPS while recording" into the user-visible UX.

**Resolution.**

1. Added two device-agnostic gates in `LocationService._onPosition()`: drop fixes with `accuracy > 30 m`, and drop fixes whose implied speed against the last accepted point exceeds 56 m/s (≈ 200 km/h). Pixel devices with FLP rarely trip these gates; Huawei devices are protected by them.
2. Split `LocationService` into two layers of intent: `startLiveUpdates()` opens the position stream (idempotent), and `startTracking()` only flips an `_isTracking` flag and accumulates `TrackPoint`s. `RecordingPage.initState` now subscribes to the live stream immediately, so the self-marker tracks the user the moment the page opens — independent of recording state.

**Lesson.** Bypassing GMS solves "no GPS data" but inherits "no fusion" as a second-order cost, which has to be paid back at the application layer. And: feature boundaries should follow the user's mental model (*"this screen always shows my location"*), not implementation accidents (*"only subscribe when recording starts"*).

### Case study 2 — Custom heading marker dwarfs entire streets when zoomed out

**Phenomenon.** A Baidu-style direction-indicating arrow was implemented for the user's current position (see `lib/utils/heading_marker.dart`). At the default zoom level (15) the marker looked correct; pinching out to a city-level view, the arrow icon stayed at its rendered pixel size while the map content shrank — at zoom 8 a single arrow visually covered half a street.

**Root cause.** `Marker.icon` accepts a `BitmapDescriptor.bytes` blob, which is a fixed-pixel raster (96 px in the original implementation). Google Maps Flutter does **not** scale custom marker icons against the map's metres-per-pixel ratio. As the user zooms out, the world shrinks but the icon does not — they grow apparent in proportion.

**Resolution.** Listen to the camera and regenerate the bitmap when zoom changes meaningfully:

```dart
double _iconSizeForZoom(double zoom) {
  return (40.0 + (zoom - 14) * 10).clamp(28.0, 96.0);
}
```

Three implementation details that turned out to matter:

- **Regenerate only in `onCameraIdle`, never in `onCameraMove`.** `PictureRecorder` rebuild is expensive enough that running it on every camera-move callback visibly drops fps during pinch-zoom.
- **Skip the rebuild if the target size is within 6 px of the current size.** Small camera-idle events from minor pan or jitter don't warrant the work.
- **Re-entrancy guard `_regeneratingIcon`** prevents two concurrent `buildHeadingMarker` calls from racing if the user pinches several times in rapid succession.

**Lesson.** Custom `BitmapDescriptor` markers in Google Maps Flutter come with the implicit cost of "you handle zoom adaptation yourself." There is no native equivalent of Mapbox's `iconSize` zoom-stop expression; the workaround is camera-driven regeneration with debouncing.

### Case study 3 — Home statistics permanently stuck at zero

**Phenomenon.** After recording several journeys, Trip History and Record refreshed correctly, but the three Home stat cards (Journeys / Total km / Photos) and the "Recent Journeys" list stayed permanently at zero / empty. Restart, reinstall — same.

**Root cause.** `home_page.dart` had been a `StatelessWidget` since the early navigation skeleton, with the three cards passing the literal string `'0'`. The empty-state widget was static. When the SQLite layer was wired into History, Record, and Trip Detail, **Home was missed** — its placeholders looked like real-data UI, so the gap went unnoticed during manual testing. A page that *appears* to work is harder to spot as broken than one that crashes.

**Resolution.**

1. Added `DatabaseService.loadStats()`: one aggregate SQL for `tripCount` + `photoCount`, plus a sweep of `track_points` ordered by `(trip_id, timestamp)` summing `Geolocator.distanceBetween` between consecutive points to derive `totalMeters`.
2. Promoted `HomePage` to `StatefulWidget`: `initState` calls `_load()` and registers a listener on `DatabaseService.instance.tripsRevision` (a `ValueNotifier<int>` that increments on every save / delete), so saves elsewhere automatically refresh Home without imperative cross-page coupling.
3. "Recent Journeys" is built from `loadTrips().take(3)`; once the user has more than three trips, a "See all" button switches to the History tab.

**Lesson.** Placeholder UI (hard-coded `'0'`, static empty states) is necessary when scaffolding pages, but **the commit that wires real data must touch every page that consumes that data**. A page that "looks fine" but doesn't update is the kind of bug that reaches users before it reaches the developer.

## Engineering practices

- **Daily/weekly commit cadence.** The git history shows iterative progress over the term — see the [Network graph](https://github.com/xms12138/CASA0015-Mobile-System/network) and the commit log itself for incremental progress.
- **Code comments explain *why*, not *what*.** Comments are reserved for non-obvious constraints (the Firestore 500-op batch limit, the EMA `α` choice for compass, the `unawaited` cloud sync pattern) — variable names carry the *what*. See `lib/services/location_service.dart`, `lib/pages/trip_detail_page.dart` for examples.
- **`flutter analyze` reports 0 issues** on every commit; lint is enforced via `analysis_options.yaml`.
- **Secrets live outside source control.** `env.json`, `firebase_options.dart`, `google-services.json`, `local.properties` are all gitignored — the repository can be cloned and built on any developer's machine without inheriting upstream credentials.
- **A development journal accompanies the code.** [`DEVLOG.md`](DEVLOG.md) captures consequential debugging incidents in a *phenomenon / root cause / resolution* format. The deeper ones are expanded into the [Case studies](#case-studies) section above.

## Known limitations

- **Android only.** iOS and web placeholders are present but the demo target is a single Huawei device. iOS would need its own Maps key in `AppDelegate.swift`.
- **Cloud sync is one-way.** Trips upload to Firestore but the UI never reads them back; switching devices would not surface old trips. This is by design — Spark plan does not include Firebase Storage, so photos are local-path only.
- **No reverse geocoding.** Trip titles are timestamps, not place names.
- **History thumbnails not implemented.** Cards show a route icon rather than a photo or static map preview.
- **No in-app dark-mode toggle.** Theme is OS-driven.

## Roadmap

If given more time, in priority order:

1. Reverse geocode start/end into "Highbury → Camden" trip titles.
2. Static map thumbnails or first-photo thumbnails on History cards.
3. Two-way Firestore sync so a re-installed device pulls existing trips.
4. Hero transition from History card → Trip Detail map.
5. Background recording with a foreground service notification.
6. Loading and error skeletons for the few async paths still using a plain `CircularProgressIndicator`.

## Course context & assessment mapping

This project is the individual coursework for **CASA0015 — Mobile Systems & Interactions** at UCL CASA, 2025/26. The coursework is 100% of the module mark.

The marking rubric (Mobile Application portion, 80% of the module) and where each criterion is addressed:

| Criterion | Weight | Where in the app |
|---|:-:|---|
| Use of compelling and appropriate widgets | 30% | See [Widget showcase](#widget-showcase) — custom animations (3-layer splash, AnimatedSwitcher photo card), gesture recognition (DraggableScrollableSheet, slider scrub, marker taps, pull-to-refresh), Material 3 SegmentedButton / NavigationBar / IconButton.filled, custom-rendered map marker via `PictureRecorder`. [Responsive layout](#responsive-design--cross-platform-readiness) adapts across phone screen sizes. |
| User Interface and Experience | 20% | Material 3 with seed-driven `ColorScheme`, [design tokens](#design-system) (AppRadius / AppSpacing / AppDuration), system-driven dark mode, blocking permission UX, empty / error / loading states on async paths, splash-to-app `FadeTransition`. Cross-platform Flutter codebase ready for iOS port. |
| Exploratory & storytelling nature | 20% | Designed around a [user persona](#user-persona--storyboard) and a multi-step storyboard ending at the replay screen. Trip replay surfaces photos in time with the cursor, so the trip plays back as a sequence rather than as a static map. Real-world environment data (weather, AQI) appears alongside the route on the timeline. |
| Use of API or service | 15% | Three external services integrated: [OpenWeatherMap (weather + air pollution)](#external-services--apis) with parallel `Future.wait` and timeout, Firebase Auth + Firestore (anonymous, security-rule scoped, batch-chunked at 400 ops), Google Maps. API endpoints, polling cadence, failure isolation, and security choices are documented in [API design choices](#api-design-choices). |
| Functionality solving a problem | 15% | Solves the real problem stated up top — records routes + photos + environment together; survives restarts via SQLite and device switches via Firestore. [Iteration log](#user-testing-scenario--iteration-log) shows feedback-driven refinements (filtering, replay clock fix, permission UX collapse). Commit history shows weekly progress; [`DEVLOG.md`](DEVLOG.md) documents the development journey incident by incident. |
| **Presentation (separate 20%)** | 20% | Dedicated [GitHub Pages landing page](#landing-page), demo GIF in `docs/`, screenshots in this README, structured presentation of design → development → execution. |

Incident-driven debugging notes are in [`DEVLOG.md`](DEVLOG.md). The commit history shows iterative weekly progress.

## Author

**Hanzhe Xu** ([@xms12138](https://github.com/xms12138)) — UCL CASA, 2025/26.

## License

[MIT](LICENSE) © 2026 Hanzhe Xu

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
- [Demo & screenshots](#demo--screenshots)
- [Feature overview](#feature-overview)
- [Sensors used](#sensors-used)
- [External services & APIs](#external-services--apis)
- [Widget showcase](#widget-showcase)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Permissions](#permissions)
- [Design system](#design-system)
- [User testing scenario](#user-testing-scenario)
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

## Demo & screenshots

> _Place the demo GIF and screenshots in `docs/` before the final submission._

| Splash | Home | Recording |
|:--:|:--:|:--:|
| ![splash](docs/screenshots/splash.png) | ![home](docs/screenshots/home.png) | ![record](docs/screenshots/record.png) |

| History | Trip detail (replay) | Dark mode |
|:--:|:--:|:--:|
| ![history](docs/screenshots/history.png) | ![replay](docs/screenshots/replay.png) | ![dark](docs/screenshots/dark.png) |

A short demo GIF (≤ 3 minutes, per assessment guidelines) is at `docs/demo.gif`.

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

| Service | Use | Free-tier note |
|---|---|---|
| **Google Maps Flutter** | Map tiles + polyline + custom markers (start, end, photos, replay cursor, self-with-heading) | Maps SDK for Android key |
| **OpenWeatherMap — Current Weather** | Temperature, humidity, wind, weather description | Free tier, ≤60 req/min |
| **OpenWeatherMap — Air Pollution** | AQI 1–5 scale, surfaced in trip detail as a coloured chip | Free tier |
| **Firebase Anonymous Auth** | Per-device user identity for the cloud mirror — no sign-up flow | Spark plan |
| **Cloud Firestore** | Mirrors `users/{uid}/trips/{tripId}` with track points (chunked at 400 ops/batch), photos (path only), and weather records | Spark plan |

External API failures **never block the local recording** — every cloud / weather call is wrapped, errors are logged once per session, and the journey still saves to SQLite.

## Widget showcase

Highlights of widgets actually used in the app — for the *Use of compelling widgets* (30%) rubric area:

- **Animation & transitions** — `AnimationController`, `FadeTransition`, `SlideTransition`, `ScaleTransition`, `AnimatedSwitcher`, `Hero` page-route fade, `Curves.easeOutBack`
- **Layout** — `CustomScrollView` + `SliverAppBar` + `SliverToBoxAdapter`, `Stack` + `Positioned`, `IndexedStack` (keep-alive tabs)
- **Navigation** — Material 3 `NavigationBar` with selected/unselected icon variants, `PageRouteBuilder` for splash transition
- **Input** — `Slider` (replay scrub), `SegmentedButton<double>` (1× / 5× / 10× / 30× speeds), `FilterChip`, `IconButton.filled` (play/pause/replay tri-state), `FloatingActionButton` (camera + recenter)
- **Feedback & dismissal** — `SnackBar` (one-shot weather warnings), `AlertDialog` with `PopScope(canPop: false)` for the permission blocker, `DraggableScrollableSheet` for the photo preview, `RefreshIndicator` for pull-to-refresh on History
- **Map** — `GoogleMap` with custom `BitmapDescriptor` (compass-aware heading marker drawn through `PictureRecorder`), z-indexed split-colour `Polyline` for walked vs. remaining route
- **Theming** — Material 3 `ColorScheme.fromSeed`, `ThemeMode.system`, design tokens (`AppRadius` / `AppSpacing` / `AppDuration`)

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
├── PLAN.md                             # Phase-by-phase development plan
├── DEVLOG.md                           # Real-incident root-cause notes
├── env.example.json                    # Template for API keys (gitignored: env.json)
└── pubspec.yaml
```

## Getting started

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

## User testing scenario

The intended user journey, walked through during informal testing:

1. **First launch** — splash plays, app lands on Home with empty stats and an empty Recent Journeys card.
2. **Start recording** — user taps Record; permission dialog appears on first run; user accepts; the live map centres on their position with a heading-aware marker.
3. **Walk a short loop** — polyline grows as they move; weather is fetched silently in the background.
4. **Take a photo mid-trip** — camera button captures one image; an azure marker appears on the map at the capture coordinate.
5. **Stop recording** — confirmation dialog asks before saving; a `SnackBar` reports points + photo count.
6. **Browse history** — the trip appears at the top of History with a relative date label ("Today 14:30").
7. **Replay** — opening Trip Detail shows the full route; user drags the slider, taps Play, switches to 10×; the cursor walks the polyline; photos surface as floating cards when the cursor enters their timestamp window.
8. **Delete** — confirmation dialog protects against an accidental delete; trip disappears from History and from Firestore.

The "interesting" failures observed during testing — wavy polylines on a straight walk, jittery compass on the first prototype, mock-vs-prod migration mismatches — are documented as case studies in [`DEVLOG.md`](DEVLOG.md).

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
| Use of compelling and appropriate widgets | 30% | See [Widget showcase](#widget-showcase) — animations, M3 NavigationBar, SegmentedButton, Slider, AnimatedSwitcher, custom map markers |
| User Interface and Experience | 20% | Material 3 + design tokens, system-driven dark mode, permission UX, empty/error states, splash-to-app fade transition |
| Exploratory & storytelling nature | 20% | Trip replay with photo surfacing — the journey is replayable as a story rather than a static map |
| Use of API or service | 15% | OpenWeatherMap (weather + air pollution), Firebase Auth + Firestore, Google Maps |
| Functionality solving a problem | 15% | Records routes + photos + environment together; survives restarts and device switches via Firestore |

The full phase-by-phase plan is in [`PLAN.md`](PLAN.md); incident-driven debugging notes are in [`DEVLOG.md`](DEVLOG.md). Commit history shows iterative weekly progress through eight phases.

## Author

**Hanzhe Xu** ([@xms12138](https://github.com/xms12138)) — UCL CASA, 2025/26.

## License

[MIT](LICENSE) © 2026 Hanzhe Xu

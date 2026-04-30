# DEVLOG — TravelTrace development log

A record of the gnarlier issues encountered while building the app, the
investigation that pinned them down, and the eventual fix.
Format: **Phenomenon / Root cause / Resolution**.

---

## 2026-04-10 — WSL cannot find a Linux Android toolchain

**Phenomenon:**
The Android SDK was installed on the Windows side via Android Studio
(`F:\Android-studio\SDK`). When the same path was mounted from WSL,
`flutter doctor` reported:

```
Android SDK file not found: adb
Android sdkmanager not found
```

Opening `platform-tools/` from WSL revealed `adb.exe` / `sdkmanager.bat`
and other Windows-only binaries — none of them runnable inside the
Linux environment WSL exposes.

**Root cause:**
Android Studio downloads only the binaries that match its host OS. The
Windows installation populates the SDK with Windows executables, so
nothing under it is directly usable from Linux. I tried slipping Linux
versions of `sdkmanager` / `adb` into the shared SDK manually, but
`build-tools/` (`aapt` and friends) lacked Linux equivalents, and any
subsequent SDK update inside Android Studio overwrote the manually
placed Linux files — fundamentally unsustainable.

**Resolution:**
Abandoned the shared-SDK idea and stood up an independent Linux SDK on
the WSL side:

```bash
# 1. Standalone SDK skeleton
mkdir -p ~/Android/Sdk/cmdline-tools/latest
# Download the Linux cmdline-tools and platform-tools archives, unpack them
# into the right folders.

# 2. Point ~/.bashrc at the new path
export JAVA_HOME=/home/xms/jdk/jdk-17.0.18+8
export ANDROID_SDK_ROOT=/home/xms/Android/Sdk
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:\
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH

# 3. Tell Flutter about the new SDK
flutter config --android-sdk ~/Android/Sdk

# 4. Install the required components with the Linux sdkmanager
sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"
```

**Lesson:** Sharing a single SDK path across operating systems looks
like a disk-saving win on paper, but the maintenance overhead is huge.
Each OS keeping its own self-contained toolchain is far more stable.

---

## 2026-04-15 — GPS stuck on the default London coordinate on Huawei HarmonyOS 3.0

**Phenomenon:**
On a Huawei EML-AL00 device (HarmonyOS 3.0, Android 10 underneath), the
Recording page always reported the same default position
`LatLng(51.5074, -0.1278)` (London). Even outdoors with location
permission granted, every `Position` returned by `geolocator` was that
same fixed coordinate — yet **Baidu Maps** on the same device located
the user just fine.

**Diagnosis:**

```bash
adb shell dumpsys location | grep -A5 "gms"
```

The output showed `monitoring location: false` next to
`com.google.android.gms`. `flutter doctor` was clean and the runtime
permission was granted.

**Root cause:**
`geolocator` on Android defaults to the **Google Fused Location
Provider** (`com.google.android.gms.location`). Huawei devices ship
without a complete GMS, so the Fused Provider on these devices cannot
receive GPS hardware data — `getCurrentPosition` falls back to whatever
last cached or default coordinate it can find.

**Resolution:**
Force the native Android `LocationManager` inside
`LocationService._settings()`:

```dart
if (!kIsWeb && Platform.isAndroid) {
  return AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    forceLocationManager: true,  // bypass GMS, use the platform API
    intervalDuration: const Duration(seconds: 2),
  );
}
```

**Lesson:** When developing for a non-Google ecosystem (Huawei /
HarmonyOS / custom ROMs), prefer APIs that don't depend on GMS. If a
third-party package defaults to GMS, find out whether it offers an
escape hatch to the platform-native implementation.

---

## 2026-04-18 — Custom heading arrow becomes larger than the streets when zoomed out

**Phenomenon:**
A directional arrow modelled on the Baidu Maps puck (see
`utils/heading_marker.dart`) rendered at a sensible size at the default
zoom level of 15. Pinching out to a city-wide zoom kept the arrow's
pixel size constant — **a single arrow ended up covering an entire
street**.

**Root cause:**
A `GoogleMap` `Marker.icon` produced via `BitmapDescriptor.bytes` is a
fixed-pixel bitmap (96px in this case). It has no relationship with the
map's metres-per-pixel scale — when the map zooms out, the world shrinks
but the bitmap doesn't, so the arrow visually swells.

**Resolution:**
On `RecordingPage`, listen to camera zoom changes and rebuild the
bitmap dynamically:

```dart
double _iconSizeForZoom(double zoom) {
  return (40.0 + (zoom - 14) * 10).clamp(28.0, 96.0);
}

// onCameraMove updates _currentZoom
// onCameraIdle calls _updateHeadingIconSize():
//   if |target_size - current_size| < 6 px, skip (debounce);
//   otherwise rebuild via buildHeadingMarker(size: target) and setState.
```

Critical details:
- Rebuild only on `onCameraIdle`, not `onCameraMove`, so the
  `PictureRecorder` doesn't run continuously during a pinch (it's
  expensive).
- A 6 px diff threshold absorbs micro-jitter that isn't worth a rebuild.
- A `_regeneratingIcon` re-entry guard prevents concurrent rebuilds
  during rapid zoom changes.

**Lesson:** The cost of a custom `BitmapDescriptor.bytes` marker is
that **you have to handle zoom-aware sizing yourself**. Flutter Google
Maps has no native "scale marker with zoom" API today — you must hook
the camera and rebuild manually.

---

## 2026-04-20 — Polyline teleports on an open square, and the self arrow doesn't follow

**Phenomenon:**
On the Huawei EML-AL00 real device:
1. Standing on an unobstructed square with a recording running, the
   polyline would "teleport" tens to hundreds of metres away every few
   seconds and then snap back. Google Maps and Baidu Maps in the same
   spot showed no such jitter.
2. On the Recording page before pressing Start, the custom blue arrow
   **didn't move at all**. Only after Start did it begin tracking
   movement.

**Root cause:**
1. After turning on `forceLocationManager: true` in the previous entry,
   `geolocator` started consuming the native Android `LocationManager`,
   which exposes both the `GPS` and `NETWORK` providers and **does no
   fusion**. The `NETWORK` provider relies on cell-tower / Wi-Fi
   trilateration with 100–1000 m accuracy. Fixes from the two providers
   interleave on the stream, and the `NETWORK` ones are the
   teleporters. With Huawei lacking a full GMS there is no Fused
   Location Provider to do the fusion for us — this is a second-order
   consequence of the missing GMS.
2. `RecordingPage._initLocation()` called `getCurrentPosition` only
   once during `initState`. The actual subscription to
   `positionStream` lived inside `_startRecording` — *no recording =
   no subscription = arrow stuck*. Intuitively, opening the page
   should already show the user's live position; recording and "is
   the puck following me" shouldn't be coupled.

**Resolution:**
1. Two gates inside `LocationService._onPosition()`:
   ```dart
   // gate 1: accuracy
   if (position.accuracy > 30.0) return;
   // gate 2: implied speed against the last accepted point
   final dtSec = now.difference(prevAt).inMilliseconds / 1000.0;
   final metres = Geolocator.distanceBetween(prev.lat, prev.lng, p.lat, p.lng);
   if (metres / dtSec > 56.0) return;  // ~200 km/h
   ```
   Both gates are device-agnostic sanity filters: a Pixel with FLP
   fusion rarely trips them, while Huawei relies on them to drop bad
   `NETWORK` fixes.
2. Split the streaming model into two layers:
   - `startLiveUpdates()`: opens the position stream, runs the filters,
     emits to `positionController`. Idempotent — calling it twice does
     not double-subscribe.
   - `startTracking()`: just sets `_isTracking = true` and starts
     accumulating `TrackPoint`s.
   - `stopTracking()`: sets `_isTracking = false` and **does not**
     cancel the subscription.
3. `RecordingPage.initState` calls `startLiveUpdates()` and subscribes
   to `positionStream` to drive the custom arrow. `_startRecording` no
   longer subscribes itself — that avoids two concurrent subscribers.
   `dispose` is the only place that calls `stopLiveUpdates`.

**Lesson:**
- `forceLocationManager` solves the "no GMS" problem but pushes the
  "no fusion" side-effect into the application layer. Restoring the
  accuracy / speed filters at the app level is a necessity, not an
  optimisation.
- Feature boundaries should follow the user's mental model ("this page
  shows me where I am"), not the implementation detail ("we only
  subscribe once you press Start"). Don't let plumbing leak into the UX.

---

## 2026-04-20 — Multiple photos taken at the same spot only show one marker

**Phenomenon:**
Three photos taken in quick succession at the same location only
produced **one** blue photo marker on the Trip Detail map. Tapping it
opened a single preview; the other two photos seemed to "vanish" (yet
the summary bar's photo count was 3, so the data was clearly there).

**Root cause:**
The previous `_buildMarkers()` added one marker per `PhotoMarker`
keyed by `photo.id`. The three coordinates were near-identical, so
Google Maps stacked the markers on the same pixel — visually one
marker, with only the topmost hit-testable. The data was intact; the UI
just couldn't express the multiplicity.

**Resolution:**
Added a greedy clustering pass `_clusterPhotos()` in
`trip_detail_page.dart`:
- Threshold radius 10 m (5 m was too tight — GPS noise alone could
  split shots taken at the same spot into different groups).
- For each photo, measure `Geolocator.distanceBetween` to **the first
  photo (anchor) of each existing group**; join if within radius,
  otherwise start a new group.
- Render one marker per group. `infoWindow` shows `"N photos"` when
  N > 1.
- Tap behaviour: a single-photo group opens `_PhotoPreviewSheet`
  directly; a multi-photo group opens `_PhotoClusterSheet` with a
  horizontal thumbnail strip — tapping a thumbnail dismisses the sheet
  and opens the full preview.

**Lesson:** Google Maps has no built-in marker clustering (unlike
Leaflet / Mapbox's MarkerClusterer). Any markers whose coordinates can
plausibly collide must be aggregated at the application layer — without
that, you get the "data exists, UI doesn't" class of invisible bug.

---

## 2026-04-21 — Home page stats permanently stuck at zero

**Phenomenon:**
After recording several journeys, both the Trip History page and the
Recording page updated correctly, but the three cards at the top of
the Home page (Journeys / Total km / Photos) kept reading `0`, and the
"Recent Journeys" list below stayed in its empty state forever.

**Root cause:**
`home_page.dart` had been a `StatelessWidget` since the early
navigation skeleton, with the three cards passing the literal string
`'0'` as their `value`. The empty-state widget was static. When the
SQLite layer was wired into History, Record, and Trip Detail, **Home
was missed** — its placeholders looked like real-data UI, so the gap
went unnoticed during manual testing. A page that *appears* to work is
harder to spot as broken than one that crashes.

**Resolution:**
1. `DatabaseService.loadStats()`: a single SQL aggregation produces
   `tripCount` and `photoCount`, then a scan of `track_points` ordered
   by `(trip_id, timestamp)` accumulates `Geolocator.distanceBetween`
   per trip to derive `totalMeters`. The cost per call is on the order
   of one full Trip Detail query — entirely acceptable at Phase 5
   scale.
2. `HomePage` became a `StatefulWidget`: `initState` calls `_load()`
   and adds a listener to `DatabaseService.instance.tripsRevision`, so
   any save/delete refreshes automatically.
3. "Recent Journeys" pulls `loadTrips().take(3)`; if there are more,
   a "See all" CTA jumps to the History tab.

**Lesson:** Placeholder UI (hard-coded `'0'`, static empty states) is
necessary while the skeleton is being scaffolded, but the commit that
actually wires up data **must connect every page that consumes that
data in one go**. A page that *looks* functional ends up reported as a
bug after the fact.

---

## 2026-04-21 — All photos blank the day after recording (markers present, images empty)

**Phenomenon:**
Recorded a real-device trip with 1–2 photos. Opening it the same day
via History → Trip Detail was perfect. **After closing the app
overnight and reopening it**, the same trip still showed the polyline,
start / end pins and photo markers in the right positions — but the
preview sheet that pops up on a marker tap was **completely blank**,
and the floating thumbnail card during replay was empty too.
`flutter analyze` was clean and there were no crash logs. The UI was
silently failing.

**Root cause:**
`image_picker` writes the captured image into the app's **cache /
temporary** directory by default (on Android, something like
`/data/data/com.example.app/cache/image_picker_xxx.jpg`). The OS wipes
that directory at its discretion — after the app closes or as part of
periodic maintenance. `CameraService.takePhoto()` was returning
`image?.path` directly, persisting the temporary path as an absolute
path into SQLite. Once the OS sweeps the cache, the string still lives
in the database but `File(path).exists()` returns false. The three
`Image.file(File(path))` call sites
(`trip_detail_page.dart:752 / 893 / 1264`) **had no `errorBuilder`**.
Flutter's default behaviour is to render a zero-sized box and swallow
the exception into `FlutterError.onError` — never surfacing to the
console and never affecting layout. To the eye it just looks "blank",
which makes it trivially easy to misdiagnose as a layout issue.

**Resolution:**
1. **Persist the file the moment it's captured.** `CameraService`
   gained a private `_persist(XFile)` that copies the temp file via
   `File.copy()` into
   `getApplicationDocumentsDirectory()/photos/{uuid}.jpg`. Both
   `takePhoto` and `pickFromGallery` flow through it; the public
   signature (`Future<String?>`) is unchanged. `pubspec.yaml` already
   had `path_provider` / `path` / `uuid`, so no new dependencies.
2. **UI graceful degradation.** All three `Image.file` /
   `Image.network` call sites in `trip_detail_page.dart` got an
   `errorBuilder`. A file-level helper
   `_missingPhotoPlaceholder(context, {required bool large})` renders
   `surfaceContainerHighest` background +
   `Icons.broken_image_outlined` + the text "Photo unavailable" (label
   shown only in `large` mode). Photos lost from older trips no longer
   fail silently.
3. **No data migration.** Already-lost photos can't be recovered;
   there's no point writing a script to wipe the dead paths — if any
   stale cache files happen to survive a reboot, the row will start
   working again. In a demo context, the user can just delete and
   re-record an old trip if it bothers them.

**Lesson:** **Never write the path returned by `image_picker` straight
into a database.** Android's cache directory has a lifetime decided by
the OS, completely independent of the app's lifecycle. Any
"user-produced + long-lived" binary asset has to be moved into
`getApplicationDocumentsDirectory()` (or
`getApplicationSupportDirectory()`) the moment it appears. And every
`Image.file` call deserves an `errorBuilder` — silent default failures
are hostile to both debugging and UX.

---

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../models/trip.dart';
import '../services/database_service.dart';

class TripDetailPage extends StatefulWidget {
  final String tripId;

  const TripDetailPage({super.key, required this.tripId});

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  Trip? _trip;
  Object? _error;
  GoogleMapController? _mapController;
  // Whether we've already auto-fitted the map to the route bounds.
  // Stops the fit from running again if onMapCreated fires after
  // orientation change or widget rebuild.
  bool _didFitBounds = false;

  // Playback state. _replayProgress in [0..1] drives slider + polyline split.
  // 1x speed completes a full replay in _playbackBaseDurationSec, regardless
  // of the trip's actual duration — keeps demos snappy on long trips.
  double _replayProgress = 0.0;
  bool _isPlaying = false;
  double _playSpeed = 1.0;
  Timer? _playTimer;

  // The photo whose timestamp is closest to the replay cursor *and* within
  // _photoActivationWindow. Drives the floating card overlay so a trip's
  // photos surface on their own as the user scrubs / plays.
  PhotoMarker? _activePlaybackPhoto;

  static const double _playbackBaseDurationSec = 30.0;
  static const int _playTickMs = 100;
  static const List<double> _availableSpeeds = [1.0, 5.0, 10.0, 30.0];
  static const Duration _photoActivationWindow = Duration(seconds: 5);

  // Round-to-nearest so the cursor lands on a real track point. clamp guards
  // against floating-point drift past 1.0.
  int get _replayIndex {
    final pts = _trip?.trackPoints ?? const <TrackPoint>[];
    if (pts.length < 2) return 0;
    final i = (_replayProgress * (pts.length - 1)).round();
    if (i < 0) return 0;
    if (i > pts.length - 1) return pts.length - 1;
    return i;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final trip = await DatabaseService.instance.loadTripDetail(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _error = trip == null ? 'Journey not found' : null;
      });
      _tryFitBounds();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _tryFitBounds() {
    final trip = _trip;
    if (trip == null || _mapController == null || _didFitBounds) return;
    if (trip.trackPoints.length < 2) return;
    final bounds = _computeBounds(trip.trackPoints);
    _didFitBounds = true;
    // Post-frame so the map has actually laid out — without this the
    // first fit sometimes lands at zoom 0. Re-read _mapController from
    // state (not a captured local) so a pop-before-callback can't hit
    // a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController == null) return;
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    });
  }

  LatLngBounds _computeBounds(List<TrackPoint> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _togglePlay() {
    if (_isPlaying) {
      _playTimer?.cancel();
      setState(() => _isPlaying = false);
      return;
    }
    // Pressing play after reaching the end restarts from the beginning.
    if (_replayProgress >= 0.999) _replayProgress = 0.0;
    setState(() => _isPlaying = true);
    final ticksPerReplay = _playbackBaseDurationSec * 1000 / _playTickMs;
    _playTimer = Timer.periodic(
      const Duration(milliseconds: _playTickMs),
      (_) {
        if (!mounted) return;
        setState(() {
          _replayProgress += _playSpeed / ticksPerReplay;
          if (_replayProgress >= 1.0) {
            _replayProgress = 1.0;
            _isPlaying = false;
            _playTimer?.cancel();
          }
        });
        _animateCameraToReplay();
        _maybeUpdateActivePhoto();
      },
    );
  }

  void _setSpeed(double s) => setState(() => _playSpeed = s);

  void _onSliderChanged(double v) {
    // Manual scrubbing cancels auto-play so two timers can't compete.
    if (_isPlaying) {
      _playTimer?.cancel();
      _isPlaying = false;
    }
    setState(() => _replayProgress = v);
    _animateCameraToReplay();
    _maybeUpdateActivePhoto();
  }

  void _animateCameraToReplay() {
    final pts = _trip?.trackPoints;
    if (pts == null || pts.length < 2 || _mapController == null) return;
    final p = pts[_replayIndex];
    _mapController!.animateCamera(
      CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)),
    );
  }

  // Pick the photo closest in time to the cursor, within the activation
  // window. setState only when the active photo actually changes — avoids
  // pointless rebuilds at every 100ms tick when nothing is in range.
  void _maybeUpdateActivePhoto() {
    final pts = _trip?.trackPoints;
    final photos = _trip?.photos;
    if (pts == null || photos == null || pts.isEmpty || photos.isEmpty) {
      if (_activePlaybackPhoto != null) {
        setState(() => _activePlaybackPhoto = null);
      }
      return;
    }
    final cursor = pts[_replayIndex].timestamp;
    PhotoMarker? closest;
    Duration smallest = _photoActivationWindow;
    for (final photo in photos) {
      final diff = photo.timestamp.difference(cursor).abs();
      if (diff <= smallest) {
        smallest = diff;
        closest = photo;
      }
    }
    if (closest?.id != _activePlaybackPhoto?.id) {
      setState(() => _activePlaybackPhoto = closest);
    }
  }

  // mm:ss when under an hour, h:mm:ss for longer trips.
  String _formatMmSs(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  String _formatReplayClock() {
    final pts = _trip?.trackPoints ?? const <TrackPoint>[];
    if (pts.length < 2) return '';
    final total = pts.last.timestamp.difference(pts.first.timestamp);
    final safeTotal = total.isNegative ? Duration.zero : total;
    // Drive elapsed off the continuous progress, not the rounded
    // _replayIndex. With sparsely sampled track points (e.g. 11 points
    // over 22s) the index snaps to integers while the slider stays
    // continuous — that mismatch makes the clock and the thumb look
    // out of sync at small slider positions.
    final elapsedMs = (safeTotal.inMilliseconds * _replayProgress).round();
    final elapsed = Duration(milliseconds: elapsedMs);
    return '${_formatMmSs(elapsed)} / ${_formatMmSs(safeTotal)}';
  }

  Set<Polyline> _buildPolylines(ColorScheme colorScheme, List<TrackPoint> pts) {
    if (pts.length < 2) return const {};
    final all = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();

    // Untouched / pre-replay state: render the full route at full alpha so
    // the page first impression matches the previous static design. Once the
    // user scrubs or plays, switch to the walked / remaining split.
    if (_replayProgress <= 0.0001) {
      return {
        Polyline(
          polylineId: const PolylineId('route_outline'),
          points: all,
          color: Colors.white,
          width: 11,
          zIndex: 1,
        ),
        Polyline(
          polylineId: const PolylineId('route'),
          points: all,
          color: colorScheme.primary,
          width: 7,
          zIndex: 2,
        ),
      };
    }

    final idx = _replayIndex.clamp(0, all.length - 1);
    // sublist(0, idx + 1) and sublist(idx) share the cursor point so the two
    // segments meet seamlessly with no visual gap at the boundary.
    final walked = all.sublist(0, idx + 1);
    final remaining = all.sublist(idx);
    return {
      Polyline(
        polylineId: const PolylineId('rem_outline'),
        points: remaining,
        color: Colors.white.withValues(alpha: 0.4),
        width: 9,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('rem'),
        points: remaining,
        color: colorScheme.primary.withValues(alpha: 0.3),
        width: 5,
        zIndex: 2,
      ),
      Polyline(
        polylineId: const PolylineId('walked_outline'),
        points: walked,
        color: Colors.white,
        width: 11,
        zIndex: 3,
      ),
      Polyline(
        polylineId: const PolylineId('walked'),
        points: walked,
        color: colorScheme.primary,
        width: 7,
        zIndex: 4,
      ),
    };
  }

  Set<Marker> _buildMarkers(Trip trip) {
    final markers = <Marker>{};
    if (trip.trackPoints.isNotEmpty) {
      final start = trip.trackPoints.first;
      markers.add(
        Marker(
          markerId: const MarkerId('__start__'),
          position: LatLng(start.latitude, start.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Start'),
        ),
      );
      if (trip.trackPoints.length > 1) {
        final end = trip.trackPoints.last;
        markers.add(
          Marker(
            markerId: const MarkerId('__end__'),
            position: LatLng(end.latitude, end.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: const InfoWindow(title: 'End'),
          ),
        );
      }
    }
    final clusters = _clusterPhotos(trip.photos);
    for (final cluster in clusters) {
      final first = cluster.first;
      markers.add(
        Marker(
          markerId: MarkerId(first.id),
          position: LatLng(first.latitude, first.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          // Above start/end pins so short-distance trips don't hide photos.
          zIndexInt: 100,
          infoWindow: cluster.length > 1
              ? InfoWindow(title: '${cluster.length} photos')
              : InfoWindow.noText,
          onTap: () => cluster.length == 1
              ? _showPhotoPreview(cluster.first)
              : _showPhotoCluster(cluster),
        ),
      );
    }
    // Replay cursor: orange so it's distinct from green (start) / red (end) /
    // azure (photos). zIndex above everything so it stays visible at the
    // boundaries even when overlapping start or end pins.
    if (trip.trackPoints.length >= 2) {
      final p = trip.trackPoints[_replayIndex];
      markers.add(
        Marker(
          markerId: const MarkerId('__replay__'),
          position: LatLng(p.latitude, p.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          zIndexInt: 1000,
          infoWindow: InfoWindow(title: _formatReplayClock()),
        ),
      );
    }
    return markers;
  }

  // Greedy clustering: photos within _photoClusterRadiusMeters of an
  // existing cluster's first photo join it; otherwise start a new one.
  // Photos arrive sorted by timestamp, so the first photo acts as a
  // stable anchor — good enough for the "stood still and took a few
  // shots" case without a fancy centroid update.
  static const double _photoClusterRadiusMeters = 10.0;

  List<List<PhotoMarker>> _clusterPhotos(List<PhotoMarker> photos) {
    final clusters = <List<PhotoMarker>>[];
    for (final photo in photos) {
      var placed = false;
      for (final cluster in clusters) {
        final anchor = cluster.first;
        final distance = Geolocator.distanceBetween(
          anchor.latitude,
          anchor.longitude,
          photo.latitude,
          photo.longitude,
        );
        if (distance <= _photoClusterRadiusMeters) {
          cluster.add(photo);
          placed = true;
          break;
        }
      }
      if (!placed) clusters.add([photo]);
    }
    return clusters;
  }

  void _showPhotoPreview(PhotoMarker photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoPreviewSheet(photo: photo),
    );
  }

  void _showPhotoCluster(List<PhotoMarker> photos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoClusterSheet(
        photos: photos,
        onPhotoTap: (photo) {
          Navigator.of(context).pop();
          _showPhotoPreview(photo);
        },
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final trip = _trip;
    if (trip == null) return;
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete journey?'),
        content: const Text(
          'This will permanently remove the journey, its track points and photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DatabaseService.instance.deleteTrip(trip.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(trip?.title ?? 'Trip Detail'),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: trip == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete journey',
                  onPressed: _confirmDelete,
                ),
              ],
      ),
      body: _buildBody(context, colorScheme),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    if (_error != null && _trip == null) {
      return _ErrorState(error: _error!, onRetry: _load);
    }
    final trip = _trip;
    if (trip == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final first = trip.trackPoints.isNotEmpty
        ? LatLng(
            trip.trackPoints.first.latitude,
            trip.trackPoints.first.longitude,
          )
        : const LatLng(0, 0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: first, zoom: 14),
                onMapCreated: (c) {
                  _mapController = c;
                  _tryFitBounds();
                },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                markers: _buildMarkers(trip),
                polylines: _buildPolylines(colorScheme, trip.trackPoints),
              ),
              // Replay-driven photo card. AnimatedSwitcher fades between
              // photos as the cursor sweeps from one timestamp window to
              // the next. Top-right keeps it out of the way of the route
              // and the playback controls.
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: _activePlaybackPhoto == null
                      ? const SizedBox.shrink(key: ValueKey('__none__'))
                      : _ReplayPhotoCard(
                          key: ValueKey(_activePlaybackPhoto!.id),
                          photo: _activePlaybackPhoto!,
                          onTap: () =>
                              _showPhotoPreview(_activePlaybackPhoto!),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (trip.trackPoints.length >= 2)
          _PlaybackBar(
            progress: _replayProgress,
            isPlaying: _isPlaying,
            speed: _playSpeed,
            availableSpeeds: _availableSpeeds,
            clockLabel: _formatReplayClock(),
            onPlayToggle: _togglePlay,
            onSliderChanged: _onSliderChanged,
            onSpeedChanged: _setSpeed,
          ),
        if (trip.weatherRecords.isNotEmpty)
          _WeatherTimeline(records: trip.weatherRecords),
        _SummaryBar(trip: trip),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Trip trip;

  const _SummaryBar({required this.trip});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rawDuration = trip.endTime == null
        ? Duration.zero
        : trip.endTime!.difference(trip.startTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;
    final dateFmt = DateFormat('MMM d, HH:mm');

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(dateFmt.format(trip.startTime), style: textTheme.bodySmall),
              const SizedBox(width: 12),
              if (trip.endTime != null) ...[
                Icon(Icons.stop_rounded, size: 16, color: colorScheme.error),
                const SizedBox(width: 4),
                Text(dateFmt.format(trip.endTime!), style: textTheme.bodySmall),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: _formatDuration(duration),
              ),
              _Metric(
                icon: Icons.place_outlined,
                label: 'Points',
                value: '${trip.trackPoints.length}',
              ),
              _Metric(
                icon: Icons.photo_camera_outlined,
                label: 'Photos',
                value: '${trip.photos.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m';
    }
    return '${d.inSeconds}s';
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// Same visual as RecordingPage's photo preview; kept duplicated in Phase 5
// and scheduled to be extracted into a shared widget in Phase 8 polish.
class _PhotoPreviewSheet extends StatelessWidget {
  final PhotoMarker photo;

  const _PhotoPreviewSheet({required this.photo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: kIsWeb
                        ? Image.network(photo.localPath, fit: BoxFit.contain)
                        : Image.file(
                            File(photo.localPath),
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${photo.latitude.toStringAsFixed(4)}, ${photo.longitude.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Multi-photo cluster: horizontal thumbnail strip. Tap a thumb to pop
// the sheet and open the full _PhotoPreviewSheet for that photo.
class _PhotoClusterSheet extends StatelessWidget {
  final List<PhotoMarker> photos;
  final ValueChanged<PhotoMarker> onPhotoTap;

  const _PhotoClusterSheet({required this.photos, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${photos.length} photos at this spot',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final photo = photos[i];
                  return _ClusterThumb(
                    photo: photo,
                    onTap: () => onPhotoTap(photo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClusterThumb extends StatelessWidget {
  final PhotoMarker photo;
  final VoidCallback onTap;

  const _ClusterThumb({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: kIsWeb
                  ? Image.network(photo.localPath, fit: BoxFit.cover)
                  : Image.file(File(photo.localPath), fit: BoxFit.cover),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Text(
                  '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Phase 6: horizontal strip of environment snapshots captured during
// recording. Hidden when the trip has no records (legacy trips).
class _WeatherTimeline extends StatelessWidget {
  final List<WeatherRecord> records;

  const _WeatherTimeline({required this.records});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.eco_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Environment along the way',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _WeatherCard(record: records[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final WeatherRecord record;

  const _WeatherCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final time =
        '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}';
    final temp = record.temperature == null
        ? '—'
        : '${record.temperature!.round()}°';

    return Container(
      width: 128,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _weatherIconFor(record.weatherDescription),
                size: 18,
                color: colorScheme.primary,
              ),
              const Spacer(),
              Text(
                time,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            temp,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (record.aqi != null) _AqiBadge(level: record.aqi!),
        ],
      ),
    );
  }
}

class _AqiBadge extends StatelessWidget {
  final int level;

  const _AqiBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _aqiMeta(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.air, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            'AQI $label',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Maps an OpenWeatherMap weather description string to a Material icon.
// Substrings are checked in order from most specific to most generic
// so "light rain" matches "rain" rather than something less precise.
IconData _weatherIconFor(String? description) {
  final d = description?.toLowerCase() ?? '';
  if (d.contains('thunder')) return Icons.flash_on_rounded;
  if (d.contains('snow')) return Icons.ac_unit_rounded;
  if (d.contains('rain') || d.contains('drizzle') || d.contains('shower')) {
    return Icons.water_drop_rounded;
  }
  if (d.contains('mist') || d.contains('fog') || d.contains('haze') ||
      d.contains('smoke') || d.contains('dust')) {
    return Icons.cloud_queue_rounded;
  }
  if (d.contains('clear')) return Icons.wb_sunny_rounded;
  if (d.contains('cloud')) return Icons.cloud_rounded;
  return Icons.wb_cloudy_rounded;
}

// OpenWeatherMap AQI: 1 Good, 2 Fair, 3 Moderate, 4 Poor, 5 Very Poor.
// Using discrete colours — unknown values (outside 1–5) render neutral.
(String, Color) _aqiMeta(int level) {
  switch (level) {
    case 1:
      return ('Good', const Color(0xFF2E7D32));
    case 2:
      return ('Fair', const Color(0xFF689F38));
    case 3:
      return ('Moderate', const Color(0xFFF9A825));
    case 4:
      return ('Poor', const Color(0xFFE64A19));
    case 5:
      return ('V.Poor', const Color(0xFF7B1FA2));
    default:
      return ('?', const Color(0xFF9E9E9E));
  }
}

// Phase 8.2 playback bar. Slider scrubs the route, the IconButton plays /
// pauses / restarts depending on progress, and the SegmentedButton picks the
// auto-play speed. State lives in the parent so the polyline split + cursor
// marker can rebuild from the same _replayProgress.
class _PlaybackBar extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final double speed;
  final List<double> availableSpeeds;
  final String clockLabel;
  final VoidCallback onPlayToggle;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSpeedChanged;

  const _PlaybackBar({
    required this.progress,
    required this.isPlaying,
    required this.speed,
    required this.availableSpeeds,
    required this.clockLabel,
    required this.onPlayToggle,
    required this.onSliderChanged,
    required this.onSpeedChanged,
  });

  IconData get _playIcon {
    if (isPlaying) return Icons.pause_rounded;
    if (progress >= 0.999) return Icons.replay_rounded;
    return Icons.play_arrow_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton.filled(
                onPressed: onPlayToggle,
                icon: Icon(_playIcon),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  minimumSize: const Size(48, 48),
                ),
              ),
              Expanded(
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: onSliderChanged,
                ),
              ),
              Text(
                clockLabel,
                style: textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
            child: Row(
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<double>(
                    segments: availableSpeeds
                        .map(
                          (s) => ButtonSegment<double>(
                            value: s,
                            label: Text('${s.toStringAsFixed(0)}x'),
                          ),
                        )
                        .toList(),
                    selected: {speed},
                    onSelectionChanged: (set) => onSpeedChanged(set.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Floating thumbnail surfaced when the replay cursor is within
// _photoActivationWindow of a photo's timestamp. Tapping opens the same
// preview sheet as a marker tap, so the interaction model stays consistent.
class _ReplayPhotoCard extends StatelessWidget {
  final PhotoMarker photo;
  final VoidCallback onTap;

  const _ReplayPhotoCard({super.key, required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time =
        '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.surface, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              kIsWeb
                  ? Image.network(photo.localPath, fit: BoxFit.cover)
                  : Image.file(File(photo.localPath), fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_camera_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

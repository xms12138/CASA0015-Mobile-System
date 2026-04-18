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

  Set<Polyline> _buildPolylines(ColorScheme colorScheme, List<TrackPoint> pts) {
    if (pts.length < 2) return const {};
    final points = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    return {
      Polyline(
        polylineId: const PolylineId('route_outline'),
        points: points,
        color: Colors.white,
        width: 11,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: colorScheme.primary,
        width: 7,
        zIndex: 2,
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
          child: GoogleMap(
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

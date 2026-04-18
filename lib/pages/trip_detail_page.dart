import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
    for (final photo in trip.photos) {
      markers.add(
        Marker(
          markerId: MarkerId(photo.id),
          position: LatLng(photo.latitude, photo.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          onTap: () => _showPhotoPreview(photo),
        ),
      );
    }
    return markers;
  }

  void _showPhotoPreview(PhotoMarker photo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoPreviewSheet(photo: photo),
    );
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

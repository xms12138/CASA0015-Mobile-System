import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trip.dart';
import '../services/database_service.dart';
import 'main_scaffold.dart';
import 'trip_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TripStats _stats = const TripStats.empty();
  List<Trip> _recentTrips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // IndexedStack keeps HomePage mounted, so initState runs once —
    // listen for DB changes so new recordings reflect in the stat
    // cards and Recent Journeys without needing a tab revisit.
    DatabaseService.instance.tripsRevision.addListener(_load);
  }

  @override
  void dispose() {
    DatabaseService.instance.tripsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stats = await DatabaseService.instance.loadStats();
      final trips = await DatabaseService.instance.loadTrips();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _recentTrips = trips.take(3).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Large app bar with greeting
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: colorScheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'TravelTrace',
                style: textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary,
                          colorScheme.primaryContainer,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    bottom: -10,
                    child: Icon(
                      Icons.travel_explore,
                      size: 140,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.route_rounded,
                        label: 'Journeys',
                        value: '${_stats.tripCount}',
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.straighten_rounded,
                        label: 'Total km',
                        value: _formatKm(_stats.totalMeters),
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.photo_library_rounded,
                        label: 'Photos',
                        value: '${_stats.photoCount}',
                        color: colorScheme.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Start recording CTA
                  _StartRecordingCard(colorScheme: colorScheme),
                  const SizedBox(height: 24),

                  // Recent journeys header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Journeys',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_stats.tripCount > _recentTrips.length)
                        TextButton(
                          onPressed: () {
                            MainScaffold.of(context)?.switchToTab(2);
                          },
                          child: const Text('See all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_recentTrips.isEmpty)
                    _EmptyJourneysState(colorScheme: colorScheme)
                  else
                    Column(
                      children: [
                        for (final trip in _recentTrips) ...[
                          _RecentTripCard(
                            trip: trip,
                            onTap: () => _openTrip(trip),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripDetailPage(tripId: trip.id)),
    );
    // Detail page may have deleted the trip — reload so stats catch up
    // even if tripsRevision already fired while we were pushed.
    if (mounted) _load();
  }

  String _formatKm(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return (meters / 1000).toStringAsFixed(1);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartRecordingCard extends StatelessWidget {
  final ColorScheme colorScheme;

  const _StartRecordingCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        MainScaffold.of(context)?.switchToTab(1);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start a New Journey',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track your route, capture moments\nand log the environment',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const _RecentTripCard({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rawDuration = trip.endTime == null
        ? Duration.zero
        : trip.endTime!.difference(trip.startTime);
    final duration = rawDuration.isNegative ? Duration.zero : rawDuration;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _relativeDate(trip.startTime),
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDuration(duration),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeDate(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final daysAgo = today.difference(that).inDays;
    final hm = DateFormat('HH:mm').format(t);
    if (daysAgo == 0) return 'Today $hm';
    if (daysAgo == 1) return 'Yesterday $hm';
    return DateFormat('yyyy-MM-dd HH:mm').format(t);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}

class _EmptyJourneysState extends StatelessWidget {
  final ColorScheme colorScheme;

  const _EmptyJourneysState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.explore_outlined,
            size: 56,
            color: colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No journeys yet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start recording to see your travels here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

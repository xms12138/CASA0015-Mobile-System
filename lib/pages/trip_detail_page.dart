import 'package:flutter/material.dart';

class TripDetailPage extends StatelessWidget {
  final String tripId;

  const TripDetailPage({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Detail')),
      body: Center(
        child: Text('Trip detail for $tripId - placeholder'),
      ),
    );
  }
}

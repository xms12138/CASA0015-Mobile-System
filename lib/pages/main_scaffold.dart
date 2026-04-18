import 'package:flutter/material.dart';
import 'home_page.dart';
import 'recording_page.dart';
import 'trip_history_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  // Allow child widgets to switch tabs
  static MainScaffoldState? of(BuildContext context) {
    return context.findAncestorStateOfType<MainScaffoldState>();
  }

  @override
  State<MainScaffold> createState() => MainScaffoldState();
}

class MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  void switchToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  // Keep pages alive when switching tabs
  static const List<Widget> _pages = [
    HomePage(),
    RecordingPage(),
    TripHistoryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Journeys',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'pages/splash_page.dart';

void main() {
  runApp(const TravelTraceApp());
}

class TravelTraceApp extends StatelessWidget {
  const TravelTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TravelTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}

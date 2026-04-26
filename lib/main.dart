import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'pages/splash_page.dart';
import 'services/firebase_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Fire-and-forget anonymous sign-in. Errors are logged but don't block
  // app startup — trips still save locally even if the cloud path fails.
  unawaited(FirebaseService.instance.ensureSignedIn());
  runApp(const TravelTraceApp());
}

class TravelTraceApp extends StatelessWidget {
  const TravelTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TravelTrace',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const SplashPage(),
    );
  }
}

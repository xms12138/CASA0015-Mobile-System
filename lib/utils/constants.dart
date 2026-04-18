// App-wide constants
class AppConstants {
  static const String appName = 'TravelTrace';
  static const String appVersion = '1.0.0';

  // Database
  static const String dbName = 'travel_trace.db';
  static const int dbVersion = 1;

  // Injected at build time via --dart-define-from-file=env.json.
  // Copy env.example.json to env.json and fill in your keys.
  static const String openWeatherApiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: '',
  );
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  // GPS tracking interval in milliseconds
  static const int gpsIntervalMs = 3000;

  // Weather fetch interval in minutes
  static const int weatherIntervalMin = 5;
}

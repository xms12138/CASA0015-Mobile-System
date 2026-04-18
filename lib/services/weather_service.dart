import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip.dart';
import '../utils/constants.dart';

// OpenWeatherMap integration: current weather + air pollution.
// Designed to be non-blocking for the recording flow — on any error
// (network, HTTP, parse, missing key) fetchAt returns null so the
// caller can keep recording GPS/photos without interruption.
class WeatherService {
  static const String _base = 'https://api.openweathermap.org/data/2.5';
  static const Duration _timeout = Duration(seconds: 10);
  static const String _placeholderKey = 'YOUR_OPENWEATHER_API_KEY';

  // Whether the configured key is a real one. If not we short-circuit
  // fetchAt to avoid flooding OpenWeatherMap with 401s.
  bool get isConfigured =>
      AppConstants.openWeatherApiKey.isNotEmpty &&
      AppConstants.openWeatherApiKey != _placeholderKey;

  Future<WeatherRecord?> fetchAt(double lat, double lng) async {
    if (!isConfigured) return null;

    final key = AppConstants.openWeatherApiKey;
    final weatherUri = Uri.parse(
      '$_base/weather?lat=$lat&lon=$lng&appid=$key&units=metric',
    );
    final airUri = Uri.parse(
      '$_base/air_pollution?lat=$lat&lon=$lng&appid=$key',
    );

    try {
      final results = await Future.wait([
        http.get(weatherUri).timeout(_timeout),
        http.get(airUri).timeout(_timeout),
      ]);
      final weatherRes = results[0];
      final airRes = results[1];
      if (weatherRes.statusCode != 200 || airRes.statusCode != 200) {
        debugPrint(
          'WeatherService non-200: weather=${weatherRes.statusCode} '
          'air=${airRes.statusCode}',
        );
        return null;
      }

      final weatherJson = json.decode(weatherRes.body) as Map<String, dynamic>;
      final airJson = json.decode(airRes.body) as Map<String, dynamic>;

      final main = weatherJson['main'] as Map<String, dynamic>?;
      final wind = weatherJson['wind'] as Map<String, dynamic>?;
      final descList = weatherJson['weather'] as List?;
      final description = (descList != null && descList.isNotEmpty)
          ? (descList.first as Map<String, dynamic>)['description'] as String?
          : null;

      // Air pollution: list[0].main.aqi is the 1–5 index.
      // 1 = Good, 2 = Fair, 3 = Moderate, 4 = Poor, 5 = Very Poor.
      final airList = airJson['list'] as List?;
      int? aqi;
      if (airList != null && airList.isNotEmpty) {
        final first = airList.first as Map<String, dynamic>;
        final airMain = first['main'] as Map<String, dynamic>?;
        aqi = airMain == null ? null : (airMain['aqi'] as num?)?.toInt();
      }

      return WeatherRecord(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        temperature: (main?['temp'] as num?)?.toDouble(),
        weatherDescription: description,
        humidity: (main?['humidity'] as num?)?.toDouble(),
        windSpeed: (wind?['speed'] as num?)?.toDouble(),
        aqi: aqi,
      );
    } catch (e) {
      debugPrint('WeatherService fetchAt failed: $e');
      return null;
    }
  }
}

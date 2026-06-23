import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL']?.trim() ?? '';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Node backend base URL from flutter.env.
  /// On Android emulator, localhost/127.0.0.1 is rewritten to 10.0.2.2 (host machine).
  /// Physical device: set BACKEND_URL to your Mac's LAN IP, e.g. http://192.168.1.5:5000
  static String get backendUrl {
    final raw = dotenv.env['BACKEND_URL']?.trim() ?? '';
    if (raw.isEmpty) return '';

    if (!kIsWeb && Platform.isAndroid) {
      final uri = Uri.tryParse(raw);
      if (uri != null &&
          (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
        return uri.replace(host: '10.0.2.2').toString();
      }
    }

    return raw;
  }
}

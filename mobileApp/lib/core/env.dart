import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL']?.trim() ?? '';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Node backend base URL, e.g. http://10.0.2.2:5000 (Android emulator) or http://192.168.x.x:5000
  static String get backendUrl =>
      dotenv.env['BACKEND_URL']?.trim() ?? '';
}

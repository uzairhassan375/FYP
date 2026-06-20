import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/student_user.dart';

const _prefsKey = 'hawk_eye_student_user';
const _prefsOnboardingKey = 'hawk_eye_seen_onboarding';

class StudentSession {
  StudentSession._();

  static final StudentSession instance = StudentSession._();

  StudentUser? _user;
  bool _hasSeenOnboarding = false;

  StudentUser? get user => _user;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  bool get isSignedIn => _user != null;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSeenOnboarding = prefs.getBool(_prefsOnboardingKey) ?? false;
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _user = StudentUser.fromJson(map);
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> setUser(StudentUser user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> markOnboardingSeen() async {
    _hasSeenOnboarding = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsOnboardingKey, true);
  }
}

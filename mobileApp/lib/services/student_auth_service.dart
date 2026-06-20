import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_user.dart';

class StudentAuthService {
  StudentAuthService(this._client);

  final SupabaseClient _client;

  /// Returns a student row only when email, password, and role `student` match.
  /// Uses RPC `student_login` (see sql/student_login.sql).
  Future<StudentUser?> signInStudent({
    required String email,
    required String password,
  }) async {
    final data = await _client.rpc<dynamic>(
      'student_login',
      params: {
        'p_email': email,
        'p_password': password,
      },
    );

    if (data == null) return null;
    if (data is! Map) return null;

    final map = Map<String, dynamic>.from(data);
    if (map['role'] != 'student') return null;

    return StudentUser.fromJson(map);
  }
}

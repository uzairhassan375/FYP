import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../core/student_session.dart';

class AppealService {
  Future<List<Map<String, dynamic>>> fetchMyAppeals() async {
    final user = StudentSession.instance.user;
    if (user == null) throw StateError('Not signed in');

    final base = Env.backendUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw StateError('BACKEND_URL is not configured in flutter.env');
    }

    final uri = Uri.parse(
      '$base/api/mobile/fine-appeals?studentUserId=${Uri.encodeComponent(user.id)}',
    );
    final response = await http.get(uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(_errorMessage(response));
  }

  Future<void> submitAppeal({
    required String fineId,
    required String message,
  }) async {
    final user = StudentSession.instance.user;
    if (user == null) throw StateError('Not signed in');

    final base = Env.backendUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw StateError('BACKEND_URL is not configured in flutter.env');
    }

    final uri = Uri.parse('$base/api/mobile/fines/$fineId/appeal');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'studentUserId': user.id,
        'message': message.trim(),
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception(_errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    String message = 'Request failed (${response.statusCode})';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final err = body['error'];
      if (err != null && '$err'.trim().isNotEmpty) message = '$err';
    } catch (_) {}
    return message;
  }
}

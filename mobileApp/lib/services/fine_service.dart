import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../core/student_session.dart';

class PayFineResult {
  const PayFineResult({
    required this.pointsUsed,
    required this.remainingBalance,
  });

  final int pointsUsed;
  final int remainingBalance;
}

class FineService {
  /// Pays a pending fine using reward points only (1 point = Rs. 1).
  Future<PayFineResult> payFine({required String fineId}) async {
    final user = StudentSession.instance.user;
    if (user == null) {
      throw StateError('Not signed in');
    }

    final base = Env.backendUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw StateError('BACKEND_URL is not configured in flutter.env');
    }

    final uri = Uri.parse('$base/api/mobile/fines/$fineId/pay');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'studentUserId': user.id}),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PayFineResult(
        pointsUsed: (body['pointsUsed'] as num?)?.toInt() ?? 0,
        remainingBalance: (body['remainingBalance'] as num?)?.toInt() ?? 0,
      );
    }

    String message = 'Could not pay fine (${response.statusCode})';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final err = body['error'];
      if (err != null && '$err'.trim().isNotEmpty) {
        message = '$err';
      }
    } catch (_) {}

    throw Exception(message);
  }
}

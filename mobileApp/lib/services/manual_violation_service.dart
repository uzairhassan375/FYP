import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/env.dart';
import '../core/student_session.dart';
import '../models/report_evidence.dart';

class ManualViolationService {
  ManualViolationService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'manual-violations';
  static const _uuid = Uuid();

  /// Uploads evidence (video or image) to Storage then inserts [manual_violations].
  /// Returns the new report id.
  Future<String> submit({
    required ReportEvidence evidence,
    required String category,
    required String description,
    String? location,
    String? subjectStudentName,
    String? subjectSapId,
    String? subjectDepartment,
  }) async {
    final reporter = StudentSession.instance.user;
    if (reporter == null) {
      throw StateError('Not signed in');
    }

    final violationId = _uuid.v4();
    final isVideo = evidence.kind == ReportEvidenceKind.video;
    final ext = isVideo ? 'mp4' : 'jpg';
    final objectPath = '${reporter.id}/$violationId.$ext';
    final contentType = isVideo ? 'video/mp4' : 'image/jpeg';

    try {
      final bytes = await evidence.file.readAsBytes();
      await _client.storage.from(_bucket).uploadBinary(
            objectPath,
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      await _client.from('manual_violations').insert({
        'id': violationId,
        'reporter_user_id': reporter.id,
        'category': category,
        'description': description,
        'location': _emptyToNull(location),
        'subject_student_name': _emptyToNull(subjectStudentName),
        'subject_sap_id': _emptyToNull(subjectSapId),
        'subject_department': _emptyToNull(subjectDepartment),
        'evidence_media_type': isVideo ? 'video' : 'image',
        'video_storage_path': isVideo ? objectPath : null,
        'image_storage_path': isVideo ? null : objectPath,
        'video_duration_seconds': isVideo ? evidence.durationSeconds : null,
        'status': 'pending',
      });

      try {
        await _requestAiReview(
          violationId: violationId,
          reporterUserId: reporter.id,
        );
      } catch (_) {
        // Report is saved; AI review is best-effort and staff can still review manually.
      }
      return violationId;
    } catch (_) {
      try {
        await _client.storage.from(_bucket).remove([objectPath]);
      } catch (_) {}
      rethrow;
    }
  }

  String? _emptyToNull(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// Ask backend to run HawkEye AI on this report (auto-fine or manual review).
  Future<void> _requestAiReview({
    required String violationId,
    required String reporterUserId,
  }) async {
    final base = Env.backendUrl;
    if (base.isEmpty) return;

    final uri = Uri.parse('$base/api/mobile/manual-violations/$violationId/analyze');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'reporterUserId': reporterUserId}),
    );
    if (response.statusCode >= 400) {
      throw StateError('AI review request failed (${response.statusCode})');
    }
  }
}

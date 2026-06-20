import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/student_session.dart';
import '../../widgets/shared/status_tag.dart';

class _SignedEvidence {
  const _SignedEvidence({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;
}

/// Manual reports you submitted (with evidence). Use the **Fines** tab for fines.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _bucket = 'manual-violations';

  String _reportFilter = 'ALL';
  List<Map<String, dynamic>> _reportRows = [];
  final Map<String, _SignedEvidence> _evidenceByReportId = {};

  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final user = StudentSession.instance.user;
    if (!Env.hasSupabaseConfig || user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = !Env.hasSupabaseConfig
              ? 'Supabase is not configured.'
              : 'Sign in to see report history.';
          _reportRows = [];
          _evidenceByReportId.clear();
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;
      final vData = await client
          .from('manual_violations')
          .select()
          .eq('reporter_user_id', user.id)
          .order('created_at', ascending: false);

      final vList = (vData as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _signEvidenceForReports(vList);

      if (mounted) {
        setState(() {
          _reportRows = vList;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _signEvidenceForReports(List<Map<String, dynamic>> rows) async {
    final client = Supabase.instance.client;
    final next = <String, _SignedEvidence>{};
    for (final r in rows) {
      final id = '${r['id']}';
      final mt = (r['evidence_media_type'] as String? ?? '').toLowerCase();
      final path = mt == 'video'
          ? r['video_storage_path'] as String?
          : r['image_storage_path'] as String?;
      if (path == null || path.trim().isEmpty) continue;
      try {
        final signed = await client.storage.from(_bucket).createSignedUrl(path.trim(), 3600);
        next[id] = _SignedEvidence(url: signed, isVideo: mt == 'video');
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _evidenceByReportId
          ..clear()
          ..addAll(next);
      });
    }
  }

  List<Map<String, dynamic>> _filteredReports() {
    switch (_reportFilter) {
      case 'APPROVED':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'approved').toList();
      case 'PENDING':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'pending').toList();
      case 'REJECTED':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'rejected').toList();
      default:
        return _reportRows;
    }
  }

  int _reportCount(String filter) {
    switch (filter) {
      case 'APPROVED':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'approved').length;
      case 'PENDING':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'pending').length;
      case 'REJECTED':
        return _reportRows.where((r) => (r['status'] as String? ?? '').toLowerCase() == 'rejected').length;
      default:
        return _reportRows.length;
    }
  }

  String _capStatus(String? raw) {
    final s = (raw ?? 'pending').toLowerCase();
    if (s.isEmpty) return 'Pending';
    return s[0].toUpperCase() + s.substring(1);
  }

  String _dateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today';
      final y = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
      if (y == 1) return 'Yesterday';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  IconData _reportStatusIcon(String statusLower) {
    if (statusLower == 'approved') return Icons.check_circle;
    if (statusLower == 'pending') return Icons.pending;
    return Icons.cancel;
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (uri == null || (scheme != 'http' && scheme != 'https')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or unsupported link.')),
        );
      }
      return;
    }
    try {
      var launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link on the device.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Report history',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2196F3)),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    'Camera-related fines and clips are on the Fines tab.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 12)),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(),
                    child: _buildReportsTab(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildReportsTab(BuildContext context) {
    final filtered = _filteredReports();
    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 48),
          Center(
            child: Text(
              'No reports in this filter.',
              style: TextStyle(color: Color(0xFF666666)),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  Expanded(child: _chip('ALL', '${_reportCount('ALL')}')),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('APPROVED', '${_reportCount('APPROVED')}')),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('PENDING', '${_reportCount('PENDING')}')),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('REJECTED', '${_reportCount('REJECTED')}')),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (i.isOdd) return const SizedBox(height: 12);
                final r = filtered[i ~/ 2];
                return _reportCard(context, r);
              },
              childCount: filtered.length * 2 - 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, String count) {
    final sel = _reportFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _reportFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF2196F3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0)),
        ),
        child: Text(
          '$label ($count)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: sel ? Colors.white : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _reportCard(BuildContext context, Map<String, dynamic> r) {
    final id = '${r['id']}';
    final category = (r['category'] as String? ?? 'Report').toString();
    final description = (r['description'] as String? ?? '').toString();
    final location = (r['location'] as String? ?? '—').toString();
    final created = r['created_at'] as String?;
    final statusLower = (r['status'] as String? ?? 'pending').toLowerCase();
    final displayStatus = _capStatus(r['status'] as String?);
    final note = (r['review_note'] as String?)?.trim();
    final staffNote = (r['reviewed_by_name'] as String?)?.trim();
    final descBlock = statusLower == 'rejected' && note != null && note.isNotEmpty
        ? '$description\n\nStaff note: $note'
        : description;
    final ev = _evidenceByReportId[id];
    final mt = (r['evidence_media_type'] as String? ?? '').toLowerCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              StatusTag(status: displayStatus, icon: _reportStatusIcon(statusLower)),
            ],
          ),
          if (staffNote != null && staffNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reviewed by $staffNote',
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            descBlock.isEmpty ? '—' : descBlock,
            style: const TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_dateLabel(created), style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
              const SizedBox(width: 8),
              const Icon(Icons.location_on, size: 14, color: Color(0xFFF44336)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Evidence (same file staff reviews)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
          ),
          const SizedBox(height: 8),
          if (ev != null && !ev.isVideo)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  ev.url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) =>
                      p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorBuilder: (_, __, ___) =>
                      _evidenceFallback(context, mt, ev.url),
                ),
              ),
            )
          else if (ev != null && ev.isVideo)
            _evidenceFallback(context, 'video', ev.url)
          else
            Text(
              'No preview${mt.isNotEmpty ? ' ($mt)' : ''}.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
        ],
      ),
    );
  }

  Widget _evidenceFallback(BuildContext context, String mediaType, String url) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mediaType == 'video' ? Icons.videocam : Icons.image_not_supported_outlined,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mediaType == 'video' ? 'Video evidence' : 'Evidence',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _openUrl(context, url),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(mediaType == 'video' ? 'Open video' : 'Open image'),
          ),
        ],
      ),
    );
  }
}

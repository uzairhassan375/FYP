import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/student_session.dart';
import '../../services/appeal_service.dart';
import '../../services/fine_service.dart';
import '../../widgets/shared/status_tag.dart';

class FinesScreen extends StatefulWidget {
  const FinesScreen({super.key});

  @override
  State<FinesScreen> createState() => _FinesScreenState();
}

class _ManualReportEvidence {
  const _ManualReportEvidence({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;
}

class _FinesScreenState extends State<FinesScreen> {
  static const _manualBucket = 'manual-violations';

  String _selectedFilter = 'ALL';
  List<Map<String, dynamic>> _rows = [];
  /// `violations.id` → public `clip_url` when a camera violation triggered the fine.
  final Map<String, String> _violationClipById = {};
  /// `manual_violations.id` → signed storage URL for report attachment (when fine was tied to a manual report).
  final Map<String, _ManualReportEvidence> _manualEvidenceByManualId = {};
  bool _loading = true;
  String? _error;
  String? _payingFineId;
  String? _appealingFineId;
  int _rewardBalance = 0;
  final Map<String, String> _appealStatusByFineId = {};
  Timer? _poll;

  final FineService _fineService = FineService();
  final AppealService _appealService = AppealService();

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
              : 'Sign in to see your fines.';
          _rows = [];
        });
      }
      return;
    }

    final studentRecordId = user.studentId?.trim();
    if (studentRecordId == null || studentRecordId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Your profile is not linked to a student record (student_id). Fines from the campus system appear here once your account is linked.';
          _rows = [];
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _loading = true);

    try {
      final data = await Supabase.instance.client
          .from('fines')
          .select()
          .eq('student_id', studentRecordId)
          .order('created_at', ascending: false);

      final list = (data as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      var rewardBalance = 0;
      final rewards = await Supabase.instance.client
          .from('rewards')
          .select('points')
          .eq('student_id', studentRecordId);
      for (final row in rewards as List<dynamic>? ?? []) {
        final m = Map<String, dynamic>.from(row as Map);
        final p = m['points'];
        if (p is num) rewardBalance += p.toInt();
      }

      await _loadViolationClips(list);
      await _loadManualReportEvidence(list);
      await _loadAppeals();
      if (mounted) {
        setState(() {
          _rows = list;
          _rewardBalance = rewardBalance;
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

  Future<void> _loadViolationClips(List<Map<String, dynamic>> fineRows) async {
    final ids = <String>{};
    for (final r in fineRows) {
      final vid = r['violation_id'];
      if (vid == null) continue;
      final s = '$vid'.trim();
      if (s.isEmpty || s == 'null') continue;
      ids.add(s);
    }
    if (ids.isEmpty) {
      if (mounted) setState(() => _violationClipById.clear());
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('violations')
          .select('id, clip_url')
          .inFilter('id', ids.toList());
      final next = <String, String>{};
      for (final row in data as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final u = map['clip_url'] as String?;
        if (u != null && u.trim().isNotEmpty) {
          next['${map['id']}'] = u.trim();
        }
      }
      if (mounted) {
        setState(() {
          _violationClipById
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _violationClipById.clear());
    }
  }

  Future<void> _loadManualReportEvidence(List<Map<String, dynamic>> fineRows) async {
    final ids = <String>{};
    for (final r in fineRows) {
      final mid = r['manual_violation_id'];
      if (mid == null) continue;
      final s = '$mid'.trim();
      if (s.isEmpty || s == 'null') continue;
      ids.add(s);
    }
    if (ids.isEmpty) {
      if (mounted) setState(() => _manualEvidenceByManualId.clear());
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('manual_violations')
          .select('id, evidence_media_type, video_storage_path, image_storage_path')
          .inFilter('id', ids.toList());
      final next = <String, _ManualReportEvidence>{};
      final client = Supabase.instance.client;
      for (final row in data as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = '${map['id']}';
        final mt = (map['evidence_media_type'] as String? ?? '').toLowerCase();
        final path = mt == 'video'
            ? map['video_storage_path'] as String?
            : map['image_storage_path'] as String?;
        if (path == null || path.trim().isEmpty) continue;
        try {
          final signed = await client.storage.from(_manualBucket).createSignedUrl(path.trim(), 3600);
          next[id] = _ManualReportEvidence(url: signed, isVideo: mt == 'video');
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _manualEvidenceByManualId
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _manualEvidenceByManualId.clear());
    }
  }

  bool _clipLooksVideo(String url) {
    final u = url.toLowerCase();
    return u.contains('.mp4') || u.contains('.webm') || u.contains('.mov') || u.contains('video');
  }

  bool _clipLooksImage(String url) {
    final u = url.toLowerCase();
    return u.contains('.jpg') ||
        u.contains('.jpeg') ||
        u.contains('.png') ||
        u.contains('.gif') ||
        u.contains('.webp');
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

  String _normStatus(Map<String, dynamic> r) {
    return (r['status'] as String? ?? 'Pending').trim();
  }

  List<Map<String, dynamic>> _filtered() {
    switch (_selectedFilter) {
      case 'PENDING':
        return _rows.where((r) => _normStatus(r) == 'Pending').toList();
      case 'PAID':
        return _rows.where((r) => _normStatus(r) == 'Paid').toList();
      case 'WAIVED':
        return _rows.where((r) => _normStatus(r) == 'Waived').toList();
      default:
        return _rows;
    }
  }

  int _countFor(String filter) {
    switch (filter) {
      case 'PENDING':
        return _rows.where((r) => _normStatus(r) == 'Pending').length;
      case 'PAID':
        return _rows.where((r) => _normStatus(r) == 'Paid').length;
      case 'WAIVED':
        return _rows.where((r) => _normStatus(r) == 'Waived').length;
      default:
        return _rows.length;
    }
  }

  double _totalAmount(Iterable<Map<String, dynamic>> list) {
    var sum = 0.0;
    for (final r in list) {
      final a = r['amount'];
      if (a is num) sum += a.toDouble();
    }
    return sum;
  }

  double _paidAmount() {
    return _totalAmount(_rows.where((r) => _normStatus(r) == 'Paid'));
  }

  double _remainingAmount() {
    return _totalAmount(_rows.where((r) => _normStatus(r) == 'Pending'));
  }

  Future<void> _loadAppeals() async {
    if (!Env.hasSupabaseConfig || StudentSession.instance.user == null) {
      if (mounted) setState(() => _appealStatusByFineId.clear());
      return;
    }
    try {
      final appeals = await _appealService.fetchMyAppeals();
      final next = <String, String>{};
      for (final a in appeals) {
        final fid = '${a['fineId'] ?? a['fine_id'] ?? ''}'.trim();
        final st = (a['status'] as String? ?? 'pending').toLowerCase();
        if (fid.isNotEmpty) next[fid] = st;
      }
      if (mounted) {
        setState(() {
          _appealStatusByFineId
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appealStatusByFineId.clear());
    }
  }

  Future<void> _submitAppeal({
    required String fineId,
    required String title,
  }) async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appeal fine'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Explain why this fine for $title should be reviewed (min. 10 characters).',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: 'Your message to discipline incharge…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit appeal'),
          ),
        ],
      ),
    );

    if (submitted != true || !mounted) return;
    final message = controller.text.trim();
    if (message.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least 10 characters.'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }

    setState(() => _appealingFineId = fineId);
    try {
      await _appealService.submitAppeal(fineId: fineId, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appeal submitted. Discipline incharge will review it.'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      await _loadAppeals();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _appealingFineId = null);
    }
  }

  String _dateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _displayTitle(Map<String, dynamic> r) {
    final vt = (r['violation_type'] as String?)?.trim();
    if (vt != null && vt.isNotEmpty) {
      return vt.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
    return 'Discipline fine';
  }

  Future<void> _confirmAndPayFine({
    required String fineId,
    required String title,
    required double amount,
  }) async {
    final pointsRequired = amount.ceil();
    if (_rewardBalance < pointsRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough reward points. Need $pointsRequired, you have $_rewardBalance.',
          ),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay fine'),
        content: Text(
          'Pay Rs. ${amount.toStringAsFixed(0)} for $title?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm pay'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _payingFineId = fineId);
    try {
      await _fineService.payFine(fineId: fineId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paid Rs. ${amount.toStringAsFixed(0)} for $title.',
          ),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _payingFineId = null);
    }
  }

  IconData _statusIcon(String status) {
    if (status == 'Paid') return Icons.check_circle;
    if (status == 'Waived') return Icons.remove_circle_outline;
    return Icons.pending;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final totalFines = _totalAmount(_rows);
    final paidAmount = _paidAmount();
    final remainingAmount = _remainingAmount();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'My Fines',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF333333)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2196F3)),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    if (_error != null && _rows.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C))),
                      ),
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Outstanding',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rs. ${remainingAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.card_giftcard, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Reward points: $_rewardBalance (1 pt = Rs. 1)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Paid',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rs. ${paidAmount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Total recorded',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rs. ${totalFines.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: _buildFilterChip('ALL', '${_countFor('ALL')}')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildFilterChip('PENDING', '${_countFor('PENDING')}')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildFilterChip('PAID', '${_countFor('PAID')}')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildFilterChip('WAIVED', '${_countFor('WAIVED')}')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No fines in this filter.',
                                style: TextStyle(color: Color(0xFF666666)),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _load(),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final r = filtered[i];
                                  final status = _normStatus(r);
                                  final amount = (r['amount'] is num) ? (r['amount'] as num).toDouble() : 0.0;
                                  final desc = (r['violation_type'] as String?) ?? 'Campus discipline fine';
                                  final created = r['created_at'] as String?;
                                  final vid = r['violation_id'] != null ? '${r['violation_id']}' : '';
                                  final clip = vid.isNotEmpty ? _violationClipById[vid] : null;
                                  final mid =
                                      r['manual_violation_id'] != null ? '${r['manual_violation_id']}'.trim() : '';
                                  final reportEv = mid.isNotEmpty ? _manualEvidenceByManualId[mid] : null;
                                  return _buildFineCard(
                                    context,
                                    fine: r,
                                    fineId: '${r['id']}',
                                    title: _displayTitle(r),
                                    description: desc,
                                    date: _dateLabel(created),
                                    amount: amount,
                                    status: status,
                                    statusIcon: _statusIcon(status),
                                    violationClipUrl: clip,
                                    reportEvidence: reportEv,
                                    rewardBalance: _rewardBalance,
                                    appealStatus: _appealStatusByFineId['${r['id']}'],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterChip(String label, String count) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          '$label ($count)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _buildFineCard(
    BuildContext context, {
    required Map<String, dynamic> fine,
    required String fineId,
    required String title,
    required String description,
    required String date,
    required double amount,
    required String status,
    required IconData statusIcon,
    String? violationClipUrl,
    _ManualReportEvidence? reportEvidence,
    required int rewardBalance,
    String? appealStatus,
  }) {
    final clip = violationClipUrl?.trim();
    final hasClip = clip != null && clip.isNotEmpty;
    final isVideo = hasClip && _clipLooksVideo(clip);
    final isImage = hasClip && !isVideo && _clipLooksImage(clip);
    final pointsRequired = amount.ceil();
    final canPayWithPoints = rewardBalance >= pointsRequired;
    final appeal = (appealStatus ?? '').toLowerCase();
    final hasAppeal = appeal.isNotEmpty;
    final appealPending = appeal == 'pending';

    final repUrl = reportEvidence?.url.trim();
    final hasReport = repUrl != null && repUrl.isNotEmpty;
    final repIsVideo = hasReport && (reportEvidence?.isVideo ?? false);
    final repIsImage = hasReport && !repIsVideo && _clipLooksImage(repUrl);

    return Container(
      padding: const EdgeInsets.all(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              StatusTag(status: status, icon: statusIcon),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Reason: $description',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
              height: 1.4,
            ),
          ),
          if (fine['manual_violation_id'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Linked discipline report: ${fine['manual_violation_id']}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ],
          if (hasReport) ...[
            const SizedBox(height: 10),
            _clipOpenRow(context, repUrl, isVideo: repIsVideo, label: 'Report Evidence'),
          ] else if (fine['manual_violation_id'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Report evidence is not available.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ],
          if (hasClip) ...[
            const SizedBox(height: 10),
            _clipOpenRow(context, clip, isVideo: isVideo, label: 'Camera Violation Clip'),
          ] else if (fine['violation_id'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Camera clip is not available.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Amount',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs. ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF44336),
                      ),
                    ),
                  ],
                ),
              ),
              if (status == 'Pending')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _payingFineId == fineId || !canPayWithPoints || appealPending
                          ? null
                          : () => _confirmAndPayFine(
                                fineId: fineId,
                                title: title,
                                amount: amount,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFBDBDBD),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: _payingFineId == fineId
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(canPayWithPoints ? 'Pay' : 'Insufficient balance'),
                    ),
                    if (!hasAppeal) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _appealingFineId == fineId
                            ? null
                            : () => _submitAppeal(fineId: fineId, title: title),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2196F3),
                          side: const BorderSide(color: Color(0xFF2196F3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        child: _appealingFineId == fineId
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Appeal'),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          if (status == 'Pending' && appealPending) ...[
            const SizedBox(height: 8),
            Text(
              'Appeal pending review by discipline incharge.',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
            ),
          ] else if (hasAppeal && appeal == 'approved') ...[
            const SizedBox(height: 8),
            Text(
              'Appeal approved — fine waived.',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700),
            ),
          ] else if (hasAppeal && appeal == 'rejected') ...[
            const SizedBox(height: 8),
            Text(
              'Appeal rejected. You may pay the fine or contact incharge.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ],
          if (status == 'Pending' && !canPayWithPoints && !appealPending) ...[
            const SizedBox(height: 8),
            Text(
              'Earn reward points by submitting reports that AI confirms (500 pts each).',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF999999)),
              const SizedBox(width: 4),
              Text(
                'Issued: $date',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF999999),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clipOpenRow(BuildContext context, String url, {required bool isVideo, required String label}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                color: isVideo ? Colors.red.shade400 : Colors.blue.shade400,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF444444)),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => _openUrl(context, url),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF2196F3)),
            label: Text(
              isVideo ? 'Watch Clip' : 'View Image',
              style: const TextStyle(fontSize: 12, color: Color(0xFF2196F3), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

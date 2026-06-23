import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/student_session.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;
  DateTime? _lastLoadedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    final user = StudentSession.instance.user;
    if (!Env.hasSupabaseConfig || user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = !Env.hasSupabaseConfig
              ? 'Supabase is not configured.'
              : 'Sign in to see rewards.';
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
              'Your profile is not linked to a student record (student_id). Ask an admin to link your account so rewards can appear.';
          _rows = [];
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _loading = true);

    try {
      final data = await Supabase.instance.client
          .from('rewards')
          .select()
          .eq('student_id', studentRecordId)
          .order('created_at', ascending: false);

      final list = (data as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _rows = list;
          _error = null;
          _loading = false;
          _lastLoadedAt = DateTime.now();
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

  int _totalPoints() {
    var sum = 0;
    for (final r in _rows) {
      final p = r['points'];
      if (p is num) sum += p.toInt();
    }
    return sum;
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _updatedLabel() {
    final t = _lastLoadedAt;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalPoints();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Rewards',
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
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                      Text(_error!, textAlign: TextAlign.center),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_lastLoadedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _updatedLabel(),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2196F3).withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Total Points',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$total',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _rows.isEmpty ? 'No rewards yet' : '${_rows.length} reward(s)',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Recent rewards',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'When an admin approves your report and assigns points, they appear here.',
                            style: TextStyle(color: Color(0xFF666666)),
                          ),
                        )
                      else
                        ..._rows.map((r) {
                          final pts = r['points'];
                          final desc = (r['description'] as String?)?.trim();
                          final issuedBy = (r['issued_by'] as String?)?.trim();
                          final created = r['created_at'] as String?;
                          final line = (desc != null && desc.isNotEmpty) ? desc : 'Reward';
                          final ptsStr = pts is int ? '$pts' : (pts is num ? '${pts.toInt()}' : '0');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: const Icon(Icons.star, color: Color(0xFF4CAF50), size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF333333),
                                          ),
                                        ),
                                        if (issuedBy != null && issuedBy.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Issued by $issuedBy',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF666666),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          _timeLabel(created),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF999999),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '+$ptsStr',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4CAF50),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (_error != null && _rows.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C)),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/student_session.dart';
import '../../routes/app_routes.dart';
import '../../widgets/shared/bottom_nav_bar.dart';
import '../../widgets/shared/stat_card.dart';
import '../fines/fines_screen.dart';
import '../history/history_screen.dart';
import '../report/report_screen.dart';
import '../rewards/rewards_screen.dart';
import 'widgets/home_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final GlobalKey<HomeContentState> _homeContentKey = GlobalKey<HomeContentState>();

  late final List<Widget> _screens = [
    HomeContent(key: _homeContentKey),
    ReportScreen(
      onReportSubmitted: () {
        _homeContentKey.currentState?.refreshStats();
        setState(() => _currentIndex = 0);
      },
    ),
    const FinesScreen(),
    const RewardsScreen(),
    const HistoryScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      _homeContentKey.currentState?.refreshStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

  @override
  HomeContentState createState() => HomeContentState();
}

class HomeContentState extends State<HomeContent> {
  int _totalReports = 0;
  int _approved = 0;
  int _pending = 0;
  int _rewardPoints = 0;
  double _outstandingFines = 0;
  List<Map<String, dynamic>> _recentReports = [];
  String? _statsError;
  bool _statsLoading = true;
  Timer? _poll;

  /// Call after login, tab switch to Home, or a new report from the Report tab.
  Future<void> refreshStats() => _loadStats();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _loadStats(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadStats({bool silent = false}) async {
    final user = StudentSession.instance.user;
    if (!Env.hasSupabaseConfig || user == null) {
      if (mounted) {
        setState(() {
          _statsLoading = false;
          _statsError = null;
          _totalReports = 0;
          _approved = 0;
          _pending = 0;
          _rewardPoints = 0;
          _outstandingFines = 0;
          _recentReports = [];
        });
      }
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _statsLoading = true;
        _statsError = null;
      });
    }

    try {
      final violations = await Supabase.instance.client
          .from('manual_violations')
          .select()
          .eq('reporter_user_id', user.id)
          .order('created_at', ascending: false);

      final list = (violations as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      var approved = 0;
      var pending = 0;
      for (final r in list) {
        final s = (r['status'] as String? ?? '').toLowerCase();
        if (s == 'approved') approved++;
        if (s == 'pending') pending++;
      }

      var rewardSum = 0;
      var outstandingSum = 0.0;
      final sid = user.studentId?.trim();
      if (sid != null && sid.isNotEmpty) {
        final rewards = await Supabase.instance.client.from('rewards').select('points').eq('student_id', sid);
        final rlist = rewards as List<dynamic>? ?? [];
        for (final row in rlist) {
          final m = row as Map<String, dynamic>;
          final p = m['points'];
          if (p is num) rewardSum += p.toInt();
        }

        final fines = await Supabase.instance.client
            .from('fines')
            .select('amount, status')
            .eq('student_id', sid);
        final flist = fines as List<dynamic>? ?? [];
        for (final row in flist) {
          final m = row as Map<String, dynamic>;
          if ((m['status'] as String? ?? 'Pending').trim() != 'Pending') continue;
          final amount = m['amount'];
          if (amount is num) outstandingSum += amount.toDouble();
        }
      }

      if (mounted) {
        setState(() {
          _statsLoading = false;
          _recentReports = list.take(3).toList();
          _totalReports = list.length;
          _approved = approved;
          _pending = pending;
          _rewardPoints = rewardSum;
          _outstandingFines = outstandingSum;
          _statsError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statsLoading = false;
          _statsError = e.toString();
        });
      }
    }
  }

  String _finesLabel() => 'Rs. ${_outstandingFines.toStringAsFixed(0)} outstanding';

  String _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  (IconData, Color, String, String?) _activityFor(Map<String, dynamic> r) {
    final status = (r['status'] as String? ?? 'pending').toLowerCase();
    final category = (r['category'] as String? ?? 'Report').toString();
    if (status == 'approved') {
      return (Icons.check_circle, const Color(0xFF4CAF50), '$category report approved', null);
    }
    if (status == 'rejected') {
      return (Icons.cancel, const Color(0xFFF44336), '$category report rejected', null);
    }
    return (Icons.pending, const Color(0xFFFF9800), '$category report submitted', null);
  }

  Widget _activityHomeCard(Map<String, dynamic> r) {
    final created = r['created_at'] as String?;
    final (icon, color, title, points) = _activityFor(r);
    return HomeCard(
      icon: icon,
      iconColor: color,
      title: title,
      time: _relativeTime(created),
      points: points,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF2196F3),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            StudentSession.instance.user?.name ??
                                StudentSession.instance.user?.email.split('@').first ??
                                'Student',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 26),
                      onPressed: () async {
                        await StudentSession.instance.clear();
                        if (!context.mounted) return;
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          AppRoutes.login,
                          (_) => false,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reward Points',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    StudentSession.instance.user?.studentId == null ||
                                            StudentSession.instance.user!.studentId!.trim().isEmpty
                                        ? 'Not Linked'
                                        : '$_rewardPoints Pts',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Outstanding',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Rs. ${_outstandingFines.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadStats(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_statsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(
                                'Loading your stats…',
                                style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          StatCard(
                            title: 'Total',
                            value: '$_totalReports',
                            icon: Icons.description,
                            iconColor: const Color(0xFF2196F3),
                          ),
                          const SizedBox(width: 12),
                          StatCard(
                            title: 'Approved',
                            value: '$_approved',
                            icon: Icons.check_circle,
                            iconColor: const Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 12),
                          StatCard(
                            title: 'Pending',
                            value: '$_pending',
                            icon: Icons.pending,
                            iconColor: const Color(0xFFFF9800),
                          ),
                        ],
                      ),
                    ],
                  if (!_statsLoading && _statsError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statsError!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Report Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final submitted = await Navigator.pushNamed<Object?>(context, AppRoutes.report);
                        if (mounted && submitted == true) {
                          await _loadStats();
                        }
                      },
                      icon: const Icon(Icons.warning, color: Colors.white),
                      label: const Text(
                        'Report a Violation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Recent Activity
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, AppRoutes.history);
                        },
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!_statsLoading && _recentReports.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No recent activity yet. Submit a report from the Report tab.',
                        style: TextStyle(color: Color(0xFF666666)),
                      ),
                    )
                  else if (!_statsLoading)
                    ...[
                      for (var i = 0; i < _recentReports.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _activityHomeCard(_recentReports[i]),
                      ],
                    ],
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

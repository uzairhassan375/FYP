import 'package:flutter/material.dart';

import '../../core/student_session.dart';
import '../../routes/app_routes.dart';

class FirstTimeSplashScreen extends StatefulWidget {
  const FirstTimeSplashScreen({super.key});

  @override
  State<FirstTimeSplashScreen> createState() => _FirstTimeSplashScreenState();
}

class _FirstTimeSplashScreenState extends State<FirstTimeSplashScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_SplashPageData> _pages = const [
    _SplashPageData(
      icon: Icons.security,
      title: 'Welcome to Hawk Eye',
      description: 'Monitor campus discipline and help keep your environment safe.',
    ),
    _SplashPageData(
      icon: Icons.report_problem,
      title: 'Report Quickly',
      description: 'Submit violations with media evidence in a few taps.',
    ),
    _SplashPageData(
      icon: Icons.emoji_events,
      title: 'Track Points and Fines',
      description: 'Check your reward points and fines from the home dashboard.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await StudentSession.instance.markOnboardingSeen();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      StudentSession.instance.isSignedIn ? AppRoutes.home : AppRoutes.login,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Hawk Eye',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF2196F3),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (_, index) {
                    final page = _pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: const Color(0xFFE3F2FD),
                          child: Icon(page.icon, size: 56, color: const Color(0xFF2196F3)),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B1B1B),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF666666),
                            height: 1.5,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: _currentPage == index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index ? const Color(0xFF2196F3) : const Color(0xFFB0BEC5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    if (isLastPage) {
                      await _finishOnboarding();
                      return;
                    }
                    await _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Text(isLastPage ? 'Get Started' : 'Next'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _finishOnboarding,
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashPageData {
  final IconData icon;
  final String title;
  final String description;

  const _SplashPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

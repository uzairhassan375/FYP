import 'package:flutter/material.dart';

/// Main shell navigation. Uses [NavigationBar] (Material 3) so labels like **Fines**
/// always match code — avoids any stale `BottomNavigationBar` item cache from hot reload.
class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: 'Home',
          tooltip: 'Home',
        ),
        NavigationDestination(
          icon: const Icon(Icons.report_outlined),
          selectedIcon: const Icon(Icons.report),
          label: 'Report',
          tooltip: 'Submit report',
        ),
        NavigationDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet),
          label: 'Fines',
          tooltip: 'My fines',
        ),
        NavigationDestination(
          icon: const Icon(Icons.card_giftcard_outlined),
          selectedIcon: const Icon(Icons.card_giftcard),
          label: 'Rewards',
          tooltip: 'Rewards',
        ),
        NavigationDestination(
          icon: const Icon(Icons.history),
          selectedIcon: const Icon(Icons.history),
          label: 'History',
          tooltip: 'Report history',
        ),
      ],
    );
  }
}

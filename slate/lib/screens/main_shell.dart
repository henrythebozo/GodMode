import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../state/app_state.dart';
import '../widgets/slate_nav_bar.dart';
import 'cards_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'password_sheets.dart';
import 'profile_screen.dart';
import 'transfer_screen.dart';

/// The four tabs behind the floating pill: home, transfer, cards, profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Lets any screen switch tabs (e.g. the home card opening Cards).
  static void selectTab(BuildContext context, AppTab tab) =>
      context.findAncestorStateOfType<_MainShellState>()?.select(tab.index);

  @override
  State<MainShell> createState() => _MainShellState();
}

enum AppTab { home, transfer, cards, profile }

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _visited = <int>{0};
  final _transferMode = ValueNotifier(TransferMode.send);
  AppState? _state;
  bool _leaving = false;

  static const _items = [
    NavItem(label: 'Home', icon: Iconsax.home_2_copy, selectedIcon: Iconsax.home_2),
    NavItem(
      label: 'Transfer',
      icon: Iconsax.arrow_swap_horizontal_copy,
      selectedIcon: Iconsax.arrow_swap_horizontal_copy,
    ),
    NavItem(label: 'Cards', icon: Iconsax.card_copy, selectedIcon: Iconsax.card),
    NavItem(label: 'Profile', icon: Iconsax.user_copy, selectedIcon: Iconsax.user),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.read(context);
    if (!identical(state, _state)) {
      _state?.removeListener(_onState);
      _state = state..addListener(_onState);
      _onState();
    }
  }

  void _onState() {
    final state = _state;
    if (state == null) return;
    // Logged out here or elsewhere (expired session, another device): back to login.
    if (!state.isSignedIn) {
      if (_leaving) return;
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (_, _, _) => const LoginScreen(),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
          (_) => false,
        );
      });
      return;
    }
    if (state.pendingPasswordRecovery) {
      state.pendingPasswordRecovery = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showNewPasswordSheet(context);
      });
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_onState);
    _transferMode.dispose();
    super.dispose();
  }

  void select(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  void openTransfer(TransferMode mode) {
    _transferMode.value = mode;
    select(AppTab.transfer.index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onAction: openTransfer),
      TransferScreen(mode: _transferMode),
      const CardsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < pages.length; i++)
                // Build tabs on first visit so the home intro isn't competing.
                _visited.contains(i) ? pages[i] : const SizedBox.shrink(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: SlateNavBar.bottomOffset(context),
            child: AnimatedSlide(
              // Tuck the bar away while the keyboard is up.
              offset: MediaQuery.viewInsetsOf(context).bottom > 0 ? const Offset(0, 2) : Offset.zero,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Center(
                child: SlateNavBar(items: _items, index: _index, onSelect: select),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

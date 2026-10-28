import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// Black screen with the SLATE wordmark. Hands over to the login screen
/// without a transition (its first frame is this frame), or fades into the
/// app when a session is already stored.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void initState() {
    super.initState();
    unawaited(_continue());
  }

  Future<void> _continue() async {
    final state = AppScope.read(context);
    final minimum = Future<void>.delayed(const Duration(milliseconds: 1300));
    if (state.isSignedIn) await state.refresh();
    await minimum;
    if (!mounted) return;
    final route = state.isSignedIn
        ? PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 550),
            pageBuilder: (_, _, _) => const MainShell(),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          )
        : PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const LoginScreen(),
          );
    Navigator.of(context).pushReplacement(route);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SlateColors.ink,
        body: Center(
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_intro.value);
              return Opacity(
                opacity: Curves.easeOut.transform((_intro.value * 1.6).clamp(0, 1)),
                child: SlateWordmark(letterSpacing: 16 - 10 * t),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "S L A T E" in white.
class SlateWordmark extends StatelessWidget {
  const SlateWordmark({super.key, this.letterSpacing = 6, this.fontSize = 30});

  final double letterSpacing;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'SLATE',
      style: TextStyle(
        fontFamily: SlateText.family,
        fontSize: fontSize,
        height: 1,
        fontWeight: FontWeight.w500,
        letterSpacing: letterSpacing,
        color: Colors.white,
      ),
    );
  }
}

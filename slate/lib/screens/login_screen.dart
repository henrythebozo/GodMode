import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/social_buttons.dart';
import '../widgets/wave_header.dart';
import 'main_shell.dart';
import 'password_sheets.dart';
import 'splash_screen.dart';

enum _Mode { login, signup }

/// Log in / sign up. Opens from the splash: the black curtain lifts into the
/// wave, the wordmark glides to the corner and the form staggers in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// Drops the curtain back down after signing in, before the app fades in.
  late final AnimationController _outro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  _Mode _mode = _Mode.login;
  bool _busy = false;
  SocialProvider? _socialBusy;

  @override
  void initState() {
    super.initState();
    // Let the first frame (identical to the splash) land before moving.
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _outro.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _isLogin => _mode == _Mode.login;

  void _toggleMode() {
    HapticFeedback.selectionClick();
    _form.currentState?.reset();
    setState(() => _mode = _isLogin ? _Mode.signup : _Mode.login);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    final state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      if (_isLogin) {
        await state.signIn(_email.text, _password.text);
      } else {
        final needsConfirmation = await state.signUp(_name.text, _email.text, _password.text);
        if (needsConfirmation) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _mode = _Mode.login;
          });
          showSlateSnack(context, 'Check ${_email.text.trim()} for a link to confirm your account.');
          return;
        }
      }
      await _enterApp();
    } on SlateException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      HapticFeedback.heavyImpact();
      showSlateSnack(context, e.message, error: true);
    }
  }

  Future<void> _social(SocialProvider provider) async {
    final state = AppScope.read(context);
    setState(() => _socialBusy = provider);
    try {
      await state.signInWith(provider);
      // Web OAuth leaves the app and returns signed in; native returns here.
      if (state.isSignedIn) await _enterApp();
    } on SlateException catch (e) {
      if (mounted) showSlateSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _socialBusy = null);
    }
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await _outro.forward();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const MainShell(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ------------------------------------------------------------------ layout

  /// Fade + rise for the item that starts at [start] (fraction of the intro).
  Widget _stagger(double start, Widget child) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(((_intro.value - start) / 0.32).clamp(0, 1));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 26 * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final waveBottom = WavePainter.bottomFor(size.width);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SlateColors.canvas,
        body: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(28, waveBottom + 22, 28, safe.bottom + 24),
                child: AutofillGroup(child: _buildForm()),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _outro]),
                  builder: (context, _) => CustomPaint(
                    painter: WavePainter(progress: _intro.value * (1 - _outro.value)),
                  ),
                ),
              ),
            ),
            _buildBrand(size, safe),
          ],
        ),
      ),
    );
  }

  /// Wordmark travelling from the centre (splash position) to the corner,
  /// with the subtitle appearing under it.
  Widget _buildBrand(Size size, EdgeInsets safe) {
    const logoHeight = 30.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _outro]),
      builder: (context, _) {
        final move = Curves.easeInOutCubic.transform((_intro.value / 0.62).clamp(0, 1));
        final back = Curves.easeInCubic.transform(_outro.value);
        final travel = move * (1 - back);
        final centerLeft = (size.width - _logoWidth()) / 2;
        final centerTop = (size.height - logoHeight) / 2;
        final left = centerLeft + (28 - centerLeft) * travel;
        final top = centerTop + (safe.top + 36 - centerTop) * travel;
        // Gone in the first third of the outro, before the wordmark crosses it.
        final subtitle = Curves.easeOut.transform(((_intro.value - 0.42) / 0.3).clamp(0, 1)) *
            (1 - (_outro.value * 3).clamp(0, 1));
        return Stack(
          children: [
            Positioned(left: left, top: top, child: const SlateWordmark()),
            Positioned(
              left: 28,
              top: safe.top + 36 + logoHeight + 9 + 8 * (1 - subtitle),
              child: Opacity(
                opacity: subtitle,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _isLogin
                        ? 'Welcome back! Log in to continue.'
                        : 'Create your Slate account in a minute.',
                    key: ValueKey(_mode),
                    style: SlateText.small.copyWith(
                      color: SlateColors.onInkSubtle,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double? _logoWidthCache;

  /// Laid-out width of the wordmark, so it starts exactly where the splash's
  /// centred copy sits.
  double _logoWidth() {
    if (_logoWidthCache case final width?) return width;
    final painter = TextPainter(
      text: const TextSpan(
        text: 'SLATE',
        style: TextStyle(
          fontFamily: SlateText.family,
          fontSize: 30,
          height: 1,
          fontWeight: FontWeight.w500,
          letterSpacing: 6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _logoWidthCache = width;
  }

  Widget _buildForm() {
    final state = AppScope.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stagger(
            0.40,
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                _isLogin ? 'Login' : 'Sign up',
                key: ValueKey(_mode),
                style: SlateText.headline.copyWith(fontSize: 30, letterSpacing: -1, height: 1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isLogin
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SlateTextField(
                      label: 'Full name',
                      hint: 'Enter your name',
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name.' : null,
                    ),
                  ),
          ),
          _stagger(
            0.46,
            SlateTextField(
              label: 'Email',
              hint: 'Enter your email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email address.',
            ),
          ),
          const SizedBox(height: 18),
          _stagger(
            0.52,
            SlateTextField(
              label: 'Password',
              hint: '••••••••',
              controller: _password,
              focusNode: _passwordFocus,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: [_isLogin ? AutofillHints.password : AutofillHints.newPassword],
              onSubmitted: (_) => _submit(),
              validator: (v) =>
                  (v ?? '').length < 6 ? 'Password should be at least 6 characters.' : null,
            ),
          ),
          const SizedBox(height: 18),
          _stagger(
            0.56,
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isLogin ? 1 : 0,
                child: Pressable(
                  onTap: _isLogin
                      ? () => showForgotPasswordSheet(context, initialEmail: _email.text)
                      : null,
                  child: Text('Forgot password?', style: SlateText.small.copyWith(height: 1)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _stagger(
            0.6,
            PillButton(
              label: _isLogin ? 'Login' : 'Create account',
              loading: _busy,
              onPressed: _socialBusy == null ? _submit : null,
            ),
          ),
          const SizedBox(height: 30),
          _stagger(0.66, const _OrDivider()),
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => SocialButtons(
              progress: ((_intro.value - 0.66) / 0.34).clamp(0, 1),
              busy: _socialBusy,
              onPressed: _social,
            ),
          ),
          const SizedBox(height: 28),
          _stagger(
            0.78,
            Center(
              child: Pressable(
                onTap: _busy ? null : _toggleMode,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text.rich(
                    TextSpan(
                      style: SlateText.caption.copyWith(fontSize: 13),
                      children: [
                        TextSpan(text: _isLogin ? 'New to Slate? ' : 'Already have an account? '),
                        TextSpan(
                          text: _isLogin ? 'Create an account' : 'Log in',
                          style: const TextStyle(
                            color: SlateColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (state.isDemo) ...[
            const SizedBox(height: 4),
            _stagger(
              0.82,
              Text(
                'Demo mode: any email and a 6+ character password will do.',
                textAlign: TextAlign.center,
                style: SlateText.caption.copyWith(fontSize: 11, color: SlateColors.hint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const line = SizedBox(width: 44, height: 1, child: ColoredBox(color: SlateColors.line));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line,
        const SizedBox(width: 12),
        Text('Or', style: SlateText.caption.copyWith(color: SlateColors.hint)),
        const SizedBox(width: 12),
        line,
      ],
    );
  }
}

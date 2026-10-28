import 'package:flutter/material.dart';

import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// "Forgot password?" — emails a reset link.
Future<void> showForgotPasswordSheet(BuildContext context, {String initialEmail = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ForgotPasswordSheet(initialEmail: initialEmail),
  );
}

/// Shown after someone opens the reset link from that email.
Future<void> showNewPasswordSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _NewPasswordSheet(),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: SlateText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(subtitle, style: SlateText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return _SheetFrame(
        title: 'Check your email',
        subtitle: 'If ${_email.text.trim()} has a Slate account, a reset link is on its way.',
        children: [PillButton(label: 'Done', onPressed: () => Navigator.pop(context))],
      );
    }
    return _SheetFrame(
      title: 'Reset password',
      subtitle: "We'll email you a link to choose a new one.",
      children: [
        Form(
          key: _form,
          child: SlateTextField(
            label: 'Email',
            hint: 'Enter your email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _send(),
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                ? null
                : 'Enter a valid email address.',
          ),
        ),
        InlineError(_error),
        const SizedBox(height: 24),
        PillButton(label: 'Send reset link', loading: _busy, onPressed: _send),
      ],
    );
  }
}

class _NewPasswordSheet extends StatefulWidget {
  const _NewPasswordSheet();

  @override
  State<_NewPasswordSheet> createState() => _NewPasswordSheetState();
}

class _NewPasswordSheetState extends State<_NewPasswordSheet> {
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).updatePassword(_password.text);
      if (!mounted) return;
      Navigator.pop(context);
      showSlateSnack(context, 'Password updated.', aboveNav: true);
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Choose a new password',
      subtitle: 'At least 6 characters.',
      children: [
        Form(
          key: _form,
          child: SlateTextField(
            label: 'New password',
            hint: '••••••••',
            controller: _password,
            obscure: true,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _save(),
            validator: (v) =>
                (v ?? '').length < 6 ? 'Password should be at least 6 characters.' : null,
          ),
        ),
        InlineError(_error),
        const SizedBox(height: 24),
        PillButton(label: 'Save password', loading: _busy, onPressed: _save),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  AppScope.read(context).dismissPasswordRecovery();
                  Navigator.pop(context);
                },
          child: Text('Not now', style: SlateText.small.copyWith(color: SlateColors.muted)),
        ),
      ],
    );
  }
}

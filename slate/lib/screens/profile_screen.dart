import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/slate_nav_bar.dart';
import 'password_sheets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _NameSheet(controller: controller),
    );
    controller.dispose();
    if (saved == true && context.mounted) showSlateSnack(context, 'Name updated.', aboveNav: true);
  }

  /// The shell notices the session is gone and returns to the login screen.
  Future<void> _signOut(BuildContext context) async {
    try {
      await AppScope.read(context).signOut();
    } on SlateException catch (e) {
      if (context.mounted) showSlateSnack(context, e.message, error: true, aboveNav: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final profile = state.profile;
    final safe = MediaQuery.paddingOf(context);
    final name = profile?.fullName ?? '';

    Widget row(IconData icon, String title, {String? value, VoidCallback? onTap, Color? color}) {
      return Pressable(
        onTap: onTap,
        scale: 0.985,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              Icon(icon, size: 21, color: color ?? SlateColors.text),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: SlateText.body.copyWith(color: color))),
              if (value != null)
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SlateText.caption.copyWith(fontSize: 13),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Iconsax.arrow_right_3_copy, size: 16, color: SlateColors.hint),
              ],
            ],
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, safe.top + 16, 24, SlateNavBar.reservedHeight(context)),
        children: [
          Text('Profile', style: SlateText.headline.copyWith(height: 1)),
          const SizedBox(height: 28),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: SlateColors.ink, shape: BoxShape.circle),
                child: Text(
                  initials(name),
                  style: SlateText.title.copyWith(color: Colors.white, fontSize: 21),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Slate member' : name, style: SlateText.title.copyWith(fontSize: 20)),
                    const SizedBox(height: 3),
                    Text(profile?.email ?? '', style: SlateText.caption.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Account', style: SlateText.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          row(Iconsax.user_edit_copy, 'Name', value: name, onTap: () => _editName(context, name)),
          const Hairline(indent: 35),
          row(
            Iconsax.key_copy,
            'Change password',
            onTap: () => showForgotPasswordSheet(context, initialEmail: profile?.email ?? ''),
          ),
          const Hairline(indent: 35),
          row(Iconsax.wallet_2_copy, 'Wallets', value: '${state.wallets.length} currencies'),
          const SizedBox(height: 24),
          Text('About', style: SlateText.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          row(
            Iconsax.shield_tick_copy,
            'Backend',
            value: state.isDemo ? 'Demo data on this device' : 'Supabase',
          ),
          const Hairline(indent: 35),
          row(Iconsax.info_circle_copy, 'Version', value: '1.0.0'),
          const SizedBox(height: 24),
          row(Iconsax.logout_copy, 'Log out', color: SlateColors.danger, onTap: () => _signOut(context)),
        ],
      ),
    );
  }
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.controller});

  final TextEditingController controller;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).updateName(widget.controller.text);
      if (mounted) Navigator.pop(context, true);
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
          Text('Your name', style: SlateText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text('New cards are issued with this name.', style: SlateText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 20),
          SlateTextField(
            label: 'Full name',
            controller: widget.controller,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            onSubmitted: (_) => _save(),
          ),
          InlineError(_error),
          const SizedBox(height: 24),
          PillButton(label: 'Save', loading: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

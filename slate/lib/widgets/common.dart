import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme/app_theme.dart';

/// Shrinks slightly while pressed. Used instead of ink ripples throughout.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      // An explicit label replaces the child's text instead of repeating it.
      excludeSemantics: widget.semanticLabel != null,
      onTap: enabled ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The full-width black pill ("Login", "Choose Silver").
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.light = false,
    this.height = 56,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool light;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = light ? SlateColors.field : SlateColors.ink;
    final fg = light ? SlateColors.text : Colors.white;
    final enabled = onPressed != null && !loading;
    return Pressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onPressed == null ? 0.35 : 1,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(height)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: loading
                ? SizedBox.square(
                    key: const ValueKey('spinner'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Row(
                    key: ValueKey(label),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: fg, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SlateText.body.copyWith(color: fg, fontSize: 15, letterSpacing: -0.2),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Round 44pt button on the black header (search, add).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.label,
    this.size = 44,
    this.background = SlateColors.chip,
    this.foreground = Colors.white,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final double size;
  final Color background;
  final Color foreground;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, color: foreground, size: iconSize),
      ),
    );
  }
}

/// A label above a filled field, as on the login screen.
class SlateTextField extends StatefulWidget {
  const SlateTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
    this.onChanged,
    this.suffix,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<SlateTextField> createState() => _SlateTextFieldState();
}

class _SlateTextFieldState extends State<SlateTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: SlateText.label),
        const SizedBox(height: 10),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: _hidden,
          obscuringCharacter: '•',
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          autofillHints: widget.autofillHints,
          autocorrect: !widget.obscure,
          enableSuggestions: !widget.obscure,
          validator: widget.validator,
          inputFormatters: widget.inputFormatters,
          onFieldSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          style: SlateText.small.copyWith(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: widget.suffix ??
                (widget.obscure
                    ? IconButton(
                        tooltip: _hidden ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _hidden = !_hidden),
                        icon: Icon(
                          _hidden ? Iconsax.eye_slash_copy : Iconsax.eye_copy,
                          size: 20,
                          color: SlateColors.hint,
                        ),
                      )
                    : null),
          ),
        ),
      ],
    );
  }
}

/// "Recent transactions        See all"
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: SlateText.title)),
        if (action != null)
          Pressable(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(action!, style: SlateText.caption.copyWith(fontSize: 12.5)),
            ),
          ),
      ],
    );
  }
}

/// Floating message. Pass [aboveNav] when it will appear over the tab bar.
/// Inside bottom sheets use [InlineError] instead: snackbars draw behind them.
void showSlateSnack(
  BuildContext context,
  String message, {
  bool error = false,
  bool aboveNav = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      margin: aboveNav ? const EdgeInsets.fromLTRB(16, 0, 16, 112) : null,
      content: Row(
        children: [
          Icon(
            error ? Iconsax.info_circle_copy : Iconsax.tick_circle_copy,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? const Color(0xFF2A1515) : SlateColors.ink,
    ),
  );
}

/// Error text shown in place, for forms inside bottom sheets.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Iconsax.info_circle_copy, size: 16, color: SlateColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message!,
                      style: SlateText.caption.copyWith(color: SlateColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Light hairline used between grouped rows.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: const SizedBox(height: 1, child: ColoredBox(color: SlateColors.line)),
    );
  }
}

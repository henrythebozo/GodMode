import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colours sampled from the Slate reference frames.
abstract final class SlateColors {
  static const ink = Color(0xFF000000); // headers and primary buttons
  static const pill = Color(0xFF0D0D0E); // floating nav bar
  static const text = Color(0xFF0A0A0A);
  static const muted = Color(0xFFA3A3A3); // "4:07pm", "See all"
  static const subtle = Color(0xFF949494); // "/ year"
  static const hint = Color(0xFFBDBDBD);
  static const field = Color(0xFFF6F6F6);
  static const line = Color(0xFFEDEDED);
  static const canvas = Color(0xFFFFFFFF);
  static const paper = Color(0xFFF7F5F5); // card plan picker background
  static const chip = Color(0xFF212121); // round buttons on black
  static const onInkMuted = Color(0xFF8E8E8E); // "Available balance"
  static const onInkSubtle = Color(0xFF9A9A9A); // login subtitle
  static const positive = Color(0xFF4F9A7C); // credits, "+$2,400.00"
  static const danger = Color(0xFFD14343);
  static const dot = Color(0xFFD0CDCD);
}

/// Type scale measured from the frames (Plus Jakarta Sans, tight tracking on
/// the larger sizes).
abstract final class SlateText {
  static const family = 'PlusJakartaSans';

  static const balance = TextStyle(
    fontFamily: family,
    fontSize: 40,
    fontWeight: FontWeight.w500,
    letterSpacing: -2.0,
    height: 1.1,
    color: Colors.white,
  );
  static const headline = TextStyle(
    fontFamily: family,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.2,
    height: 1.15,
    color: SlateColors.text,
  );
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    color: SlateColors.text,
  );
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    color: SlateColors.text,
  );
  static const label = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: SlateColors.text,
  );
  static const small = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: SlateColors.text,
  );
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: SlateColors.muted,
  );
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: SlateColors.ink,
      onPrimary: Colors.white,
      secondary: SlateColors.ink,
      surface: SlateColors.canvas,
      onSurface: SlateColors.text,
      error: SlateColors.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: SlateText.family,
      scaffoldBackgroundColor: SlateColors.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: SlateText.family,
        bodyColor: SlateColors.text,
        displayColor: SlateColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: SlateColors.text,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SlateColors.field,
        hintStyle: SlateText.small.copyWith(
          color: SlateColors.hint,
          fontWeight: FontWeight.w400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(SlateColors.ink, 1.2),
        errorBorder: _border(SlateColors.danger),
        focusedErrorBorder: _border(SlateColors.danger, 1.2),
        errorStyle: SlateText.caption.copyWith(color: SlateColors.danger),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: SlateColors.ink,
        selectionColor: Color(0x33000000),
        selectionHandleColor: SlateColors.ink,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SlateColors.ink,
        contentTextStyle: SlateText.small.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SlateColors.canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: SlateColors.line,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SlateColors.ink
              : const Color(0xFFDDDDDD),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SlateColors.ink,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

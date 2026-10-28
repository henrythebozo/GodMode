import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Card network wordmark drawn from the bundled font (a heavy italic "VISA"),
/// sized by its cap height.
///
/// This is a stand-in, not Visa's official artwork. Showing a network's mark
/// on a real card product requires an issuing agreement with that network.
class VisaLogo extends StatelessWidget {
  const VisaLogo({super.key, this.height = 22, this.color = const Color(0xFF1C1C1C)});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Cap height of "VISA" in Plus Jakarta Sans ExtraBold is 0.768em. The
    // line box is one em tall: 0.056em above the caps, 0.176em below.
    final fontSize = height / 0.768;
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.skewX(-0.2),
      child: Text(
        'VISA',
        style: TextStyle(
          fontFamily: SlateText.family,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          height: 1,
          letterSpacing: -0.3,
          color: color,
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

// Pieces shared by the home carousel and the Cards tab.

/// Swipe physics for the card carousels: a flick keeps going through several
/// cards, then lands exactly on one.
class CardSpinPhysics extends ScrollPhysics {
  const CardSpinPhysics({required this.extent, super.parent});

  /// Pixels of swipe per card.
  final double extent;

  @override
  CardSpinPhysics applyTo(ScrollPhysics? ancestor) => CardSpinPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Pulled past either end (iOS lets you), or flicked against one: the
    // platform physics bounce or clamp it back.
    if (position.outOfRange ||
        (velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final landing = FrictionSimulation(0.05, position.pixels, velocity).finalX;
    final target = ((landing / extent).round() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    final ahead = (target - position.pixels) * velocity > 0;
    if (velocity.abs() > tolerance.velocity && ahead && (target - position.pixels).abs() > tolerance.distance) {
      return FrictionSimulation.through(position.pixels, target, velocity, tolerance.velocity * velocity.sign);
    }
    if ((target - position.pixels).abs() < tolerance.distance && velocity.abs() < tolerance.velocity) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }
}

/// One dot per card; the current one stretches into a dash.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.page, required this.color});

  final int count;
  final ValueListenable<double> page;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: ValueListenableBuilder<double>(
        valueListenable: page,
        builder: (context, page, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 6 + 10 * (1 - (page - i).abs().clamp(0.0, 1.0)),
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color.lerp(color, color.withValues(alpha: 0.25), (page - i).abs().clamp(0.0, 1.0)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

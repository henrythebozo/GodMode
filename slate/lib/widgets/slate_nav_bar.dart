import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class NavItem {
  const NavItem({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating black pill with a white circle that slides to the selected tab.
class SlateNavBar extends StatelessWidget {
  const SlateNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  static const height = 66.0;
  static const slot = 63.0;
  static const inset = 3.0;
  static const knob = 60.0;

  /// Space the bar takes at the bottom of the screen, for scroll padding.
  static double reservedHeight(BuildContext context) =>
      height + bottomOffset(context) + 16;

  static double bottomOffset(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    return safe > 0 ? safe - 3 : 16;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: slot * items.length + inset * 2,
      decoration: BoxDecoration(
        color: SlateColors.pill,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            left: inset + index * slot + (slot - knob) / 2,
            top: (height - knob) / 2,
            child: Container(
              width: knob,
              height: knob,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
          Positioned.fill(
            left: inset,
            right: inset,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].label,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              i == index ? items[i].selectedIcon : items[i].icon,
                              key: ValueKey(i == index),
                              size: 23,
                              color: i == index ? SlateColors.ink : Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

final class TrackFeedbackIconButton extends StatelessWidget {
  const TrackFeedbackIconButton({
    super.key,
    required this.isActive,
    required this.onPressed,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeTooltip,
    required this.inactiveTooltip,
  });

  final bool isActive;
  final VoidCallback? onPressed;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String activeTooltip;
  final String inactiveTooltip;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return IconButton.filledTonal(
        tooltip: activeTooltip,
        onPressed: onPressed,
        icon: Icon(activeIcon),
      );
    }

    return IconButton(
      tooltip: inactiveTooltip,
      onPressed: onPressed,
      icon: Icon(inactiveIcon),
    );
  }
}

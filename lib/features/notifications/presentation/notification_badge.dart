import 'package:flutter/material.dart';

/// Reusable badge widget showing unread/actionable event counts.
class NotificationBadge extends StatelessWidget {
  const NotificationBadge({
    super.key,
    required this.count,
    this.isActionable = false,
  });

  final int count;
  final bool isActionable;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final bgColor = isActionable
        ? const Color(0xFFEF4444) // Red for actionable/critical
        : const Color(0xFF536CFF); // Blue/Indigo for general unread

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

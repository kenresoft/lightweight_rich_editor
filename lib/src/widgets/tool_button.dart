import 'package:flutter/material.dart';

class ToolButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;
  final String tooltip;

  const ToolButton({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: isActive ? Colors.blue : Colors.black87),
      onPressed: onPressed,
    );
  }
}

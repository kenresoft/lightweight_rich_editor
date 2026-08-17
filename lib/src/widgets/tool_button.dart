import 'package:flutter/material.dart';

/// A toolbar action button that never steals keyboard focus from the
/// editor's `TextField`.
///
/// Discovered live: every toolbar button here sits over a single,
/// always-focused `TextField`, and `IconButton` requests focus for
/// itself by default when tapped (ordinary, correct behavior for a
/// standalone button — wrong here, since it silently moves keyboard
/// focus off the editor). Concretely, that meant clicking Bold and then
/// continuing to type lost every subsequent keystroke: nothing was
/// listening on the editor's hidden text-input element anymore, because
/// focus had moved to the button that was just tapped. `canRequestFocus:
/// false` on a dedicated, persistent `FocusNode` is the standard Flutter
/// fix for exactly this "acts on a focused field without taking its
/// focus" shape — persistent (not rebuilt every `build()`) because a
/// `FocusNode` created fresh each frame is a resource leak and can drop
/// focus-related state Flutter attaches to it between frames.
class ToolButton extends StatefulWidget {
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
  State<ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<ToolButton> {
  late final FocusNode _focusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      focusNode: _focusNode,
      tooltip: widget.tooltip,
      icon: Icon(widget.icon, size: 20, color: widget.isActive ? Colors.blue : Colors.black87),
      onPressed: widget.onPressed,
    );
  }
}

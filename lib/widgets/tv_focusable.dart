import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  final bool isCircle;
  final double? borderRadius; // 新增：允许自定义圆角

  const TVFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 1.1,
    this.isCircle = false,
    this.borderRadius,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  bool _isFocused = false;

  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final double effectiveRadius = widget.isCircle ? 100 : (widget.borderRadius ?? 8);

    return Focus(
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _handleTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          transform: _isFocused 
              ? (Matrix4.identity()..scale(widget.scale)) 
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(effectiveRadius),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 3,
            ),
            boxShadow: _isFocused ? [
              BoxShadow(
                color: Colors.white.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              )
            ] : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(effectiveRadius),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

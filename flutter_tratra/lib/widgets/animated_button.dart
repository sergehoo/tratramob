// lib/widgets/animated_button.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants.dart';

class AnimatedButton extends StatefulWidget {
  final FutureOr<void> Function() onPressed;
  final Widget child;
  final bool isLoading;
  final bool enabled;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double elevation;
  final String? semanticsLabel;
  final bool hapticFeedback;

  const AnimatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.enabled = true,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.radius = 12,
    this.elevation = 0,
    this.semanticsLabel,
    this.hapticFeedback = false,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  bool _internalLoading = false;

  bool get _effectiveLoading => widget.isLoading || _internalLoading;
  bool get _interactive => widget.enabled && !_effectiveLoading;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppConstants.animationDuration,
      value: 0.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handlePress() async {
    if (!_interactive) return;
    setState(() => _internalLoading = true);
    try {
      if (widget.hapticFeedback) {
        // Haptique légère sur press (optionnel)
        // Feedback.forTap(context); // décommente si tu utilises Haptic lib
      }
      final result = widget.onPressed();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _internalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ?? AppConstants.primaryColor;
    final radius = BorderRadius.circular(widget.radius);
    final shadowColor = bg.withOpacity(0.3);

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      enabled: widget.enabled,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        onShowFocusHighlight: (_) {},
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _handlePress();
            return null;
          }),
        },
        child: IgnorePointer(
          ignoring: !_interactive,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: bg,
              elevation: widget.elevation,
              shadowColor: shadowColor,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _handlePress,
                borderRadius: radius,
                splashColor: scheme.onPrimary.withOpacity(0.08),
                highlightColor: scheme.onPrimary.withOpacity(0.06),
                onHighlightChanged: (down) {
                  if (down) {
                    _controller.forward();
                  } else {
                    _controller.reverse();
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: widget.padding,
                    child: Center(
                      child: _effectiveLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : DefaultTextStyle.merge(
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              child: widget.child,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// // widgets/animated_button.dart
// import 'package:flutter/material.dart';

// class AnimatedButton extends StatefulWidget {
//   final VoidCallback onPressed;
//   final Widget child;

//   const AnimatedButton(
//       {super.key, required this.onPressed, required this.child});

//   @override
//   State<AnimatedButton> createState() => _AnimatedButtonState();
// }

// class _AnimatedButtonState extends State<AnimatedButton>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _controller;
//   late Animation<double> _scaleAnimation;

//   @override
//   void initState() {
//     super.initState();
//     _controller = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 100),
//     );
//     _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
//       CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
//     );
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   void _onTapDown(TapDownDetails details) {
//     _controller.forward();
//   }

//   void _onTapUp(TapUpDetails details) {
//     _controller.reverse();
//     widget.onPressed();
//   }

//   void _onTapCancel() {
//     _controller.reverse();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTapDown: _onTapDown,
//       onTapUp: _onTapUp,
//       onTapCancel: _onTapCancel,
//       child: ScaleTransition(
//         scale: _scaleAnimation,
//         child: Container(
//           width: double.infinity,
//           padding: const EdgeInsets.symmetric(vertical: 16),
//           decoration: BoxDecoration(
//             color: const Color(0xFF00B14F),
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: Center(
//             child: DefaultTextStyle.merge(
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontSize: 16,
//                 fontWeight: FontWeight.w600,
//               ),
//               child: widget.child,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';

import '../theme/app_theme_extensions.dart';

class TapLoopMotion {
  TapLoopMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve entrance = Curves.easeOutQuart;
  static const Curve exit = Curves.easeInCubic;

  static Color hoverSurfaceColor(BuildContext context) {
    return context.isDark ? const Color(0xFF243044) : const Color(0xFFF4F6F8);
  }
}

class TapLoopPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final MouseCursor cursor;
  final bool enabled;
  final bool animateScale;
  final double pressedScale;
  final double hoveredScale;
  final Color? hoverColor;
  final Duration duration;

  const TapLoopPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.cursor = SystemMouseCursors.click,
    this.enabled = true,
    this.animateScale = true,
    this.pressedScale = 0.985,
    this.hoveredScale = 1.002,
    this.hoverColor,
    this.duration = TapLoopMotion.fast,
  });

  @override
  State<TapLoopPressable> createState() => _TapLoopPressableState();
}

class _TapLoopPressableState extends State<TapLoopPressable> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _setHovered(bool value) {
    if (!_enabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = !widget.animateScale || !_enabled
        ? 1.0
        : _pressed
        ? widget.pressedScale
        : _hovered
        ? widget.hoveredScale
        : 1.0;
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    return MouseRegion(
      cursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled ? widget.onTap : null,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: scale,
          duration: widget.duration,
          curve: TapLoopMotion.standard,
          child: AnimatedContainer(
            duration: widget.duration,
            curve: TapLoopMotion.standard,
            decoration: BoxDecoration(
              color: _hovered && _enabled
                  ? widget.hoverColor ??
                        TapLoopMotion.hoverSurfaceColor(context)
                  : Colors.transparent,
              borderRadius: radius,
            ),
            child: ClipRRect(borderRadius: radius, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class TapLoopHoverSurface extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color? color;
  final Color? hoverColor;
  final BoxBorder? border;
  final BoxBorder? hoverBorder;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final bool scaleOnHover;

  const TapLoopHoverSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.color,
    this.hoverColor,
    this.border,
    this.hoverBorder,
    this.padding,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
    this.scaleOnHover = false,
  });

  @override
  State<TapLoopHoverSurface> createState() => _TapLoopHoverSurfaceState();
}

class _TapLoopHoverSurfaceState extends State<TapLoopHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = _hovered && enabled
        ? widget.hoverColor ?? TapLoopMotion.hoverSurfaceColor(context)
        : widget.color ?? context.bgCard;
    final border = _hovered && enabled
        ? widget.hoverBorder ?? Border.all(color: context.borderStrongSoft)
        : widget.border ?? Border.all(color: context.borderStrongSoft);

    return MouseRegion(
      cursor: enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered && enabled && widget.scaleOnHover ? 1.002 : 1,
          duration: TapLoopMotion.fast,
          curve: TapLoopMotion.standard,
          child: AnimatedContainer(
            duration: TapLoopMotion.fast,
            curve: TapLoopMotion.standard,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: widget.borderRadius,
              border: border,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class TapLoopFadeSlide extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Offset beginOffset;

  const TapLoopFadeSlide({
    super.key,
    required this.child,
    this.duration = TapLoopMotion.normal,
    this.beginOffset = const Offset(0, 0.018),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: TapLoopMotion.entrance,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: FractionalTranslation(
            translation: Offset(
              beginOffset.dx * (1 - value),
              beginOffset.dy * (1 - value),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class TapLoopAnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const TapLoopAnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = TapLoopMotion.slow,
  });

  @override
  State<TapLoopAnimatedIndexedStack> createState() =>
      _TapLoopAnimatedIndexedStackState();
}

class _TapLoopAnimatedIndexedStackState
    extends State<TapLoopAnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  int _direction = 1;
  // Indices whose child has been shown at least once. A child is only built
  // (and therefore only has its State's initState()/data fetches fire) the
  // first time its index becomes current — tabs the user never visits stay
  // unbuilt instead of all mounting eagerly on the very first frame.
  late final Set<int> _mountedIndices;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _mountedIndices = {widget.index};
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1;
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _previousIndex = null);
      }
    });
  }

  @override
  void didUpdateWidget(TapLoopAnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != _currentIndex) {
      _direction = widget.index > _currentIndex ? 1 : -1;
      _previousIndex = _currentIndex;
      _currentIndex = widget.index;
      _mountedIndices.add(widget.index);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = TapLoopMotion.entrance.transform(_controller.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _buildLayer(i, progress),
          ],
        );
      },
    );
  }

  Widget _buildLayer(int index, double progress) {
    if (!_mountedIndices.contains(index)) {
      // Never visited: skip building this tab's subtree entirely so its
      // initState()/data fetches don't fire until the user navigates to it.
      return const SizedBox.shrink();
    }

    final isCurrent = index == _currentIndex;
    final isPrevious = index == _previousIndex;
    final shouldPaint = isCurrent || isPrevious;

    if (!shouldPaint) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: widget.children[index]),
      );
    }

    final opacity = isCurrent ? progress : 1 - progress;
    final slide = isCurrent
        ? Offset(0.018 * _direction * (1 - progress), 0)
        : Offset(-0.012 * _direction * progress, 0);

    return IgnorePointer(
      ignoring: !isCurrent,
      child: TickerMode(
        enabled: isCurrent,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: slide,
            child: widget.children[index],
          ),
        ),
      ),
    );
  }
}

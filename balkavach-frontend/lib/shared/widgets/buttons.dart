import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Filled pill CTA. Scales to 0.98 while pressed (DESIGN.md).
///
/// [gradient] reproduces the Stitch "Get Started" blue→teal fill.
/// [childSized] uses the 56 px child-mode touch height.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.gradient = false,
    this.childSized = false,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool gradient;
  final bool childSized;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = widget.foregroundColor ?? colors.onPrimary;
    final background = widget.backgroundColor ?? colors.primary;
    final height = widget.childSized ? AppTouch.childMin : 52.0;

    final content = widget.loading
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: foreground, size: 22),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.childSized ? 18 : 16,
                  ),
                ),
              ),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(widget.trailingIcon, color: foreground, size: 22),
              ],
            ],
          );

    final decoration = BoxDecoration(
      color: widget.gradient ? null : background,
      gradient: widget.gradient ? context.brand.brandGradient : null,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      boxShadow: _enabled ? AppShadows.tier2 : null,
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedOpacity(
          opacity: widget.onPressed == null ? 0.5 : 1,
          duration: const Duration(milliseconds: 150),
          child: DecoratedBox(
            decoration: decoration,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _enabled ? widget.onPressed : null,
                onHighlightChanged: _setPressed,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Center(widthFactor: 1, child: content),
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

/// Tonal pill, e.g. "Parent Gate".
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = FilledButton.styleFrom(
      backgroundColor: colors.surfaceContainer,
      foregroundColor: colors.primary,
      minimumSize: Size(dense ? 44 : 64, dense ? 44 : AppTouch.parentMin),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.md - 4 : AppSpacing.lg,
      ),
      textStyle: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    if (icon == null) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

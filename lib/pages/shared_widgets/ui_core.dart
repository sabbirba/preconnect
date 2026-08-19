part of 'package:preconnect/pages/ui_kit.dart';

class BracuSelectOption<T> {
  const BracuSelectOption({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.showLeadingIcon = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool showLeadingIcon;
}

ButtonStyle bracuOutlinedButtonStyle(
  BuildContext context, {
  Color? foregroundColor,
  Color? borderColor,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  ),
  double borderRadius = 12,
}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foregroundColor ?? BracuPalette.textPrimary(context),
    backgroundColor: Colors.transparent,
    side: BorderSide(
      color:
          borderColor ??
          BracuPalette.textSecondary(context).withValues(alpha: 0.18),
    ),
    splashFactory: NoSplash.splashFactory,
    overlayColor: Colors.transparent,
    enableFeedback: false,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    padding: padding,
  );
}

ButtonStyle bracuCompactOutlinedButtonStyle(
  BuildContext context, {
  Color? foregroundColor,
  Color? borderColor,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  ),
  double borderRadius = 12,
}) {
  return bracuOutlinedButtonStyle(
    context,
    foregroundColor: foregroundColor,
    borderColor: borderColor,
    padding: padding,
    borderRadius: borderRadius,
  );
}

ButtonStyle bracuCompactIconButtonStyle({
  Color? foregroundColor,
  Color? borderColor,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  double borderRadius = 10,
}) {
  return IconButton.styleFrom(
    foregroundColor: foregroundColor ?? BracuPalette.primary,
    side: BorderSide(
      color: borderColor ?? BracuPalette.primary.withValues(alpha: 0.18),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    padding: padding,
  );
}

class BracuActionButton extends StatelessWidget {
  const BracuActionButton({
    super.key,
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onPressed,
    this.outlined = true,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.borderRadius = 12,
    this.iconSize = 18,
    this.iconGap = 8,
    this.fontSize,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double iconSize;
  final double iconGap;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return outlined ? _buildOutlined(context) : _buildText(context);
  }

  Widget _buildSpinner(BuildContext context) {
    final spinnerColor =
        foregroundColor ??
        (outlined ? BracuPalette.textPrimary(context) : Colors.white);
    return BracuSpinner(
      size: iconSize,
      color: spinnerColor,
      strokeWidth: 2.2,
      icon: icon != null ? Icons.sync_rounded : null,
    );
  }

  Widget _buildText(BuildContext context) {
    final hasIcon = iconWidget != null || icon != null || isLoading;
    if (hasIcon) {
      return TextButton(
        onPressed: isLoading ? () {} : onPressed,
        style: _textButtonStyle(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              _buildSpinner(context)
            else if (iconWidget != null)
              iconWidget!
            else
              Icon(icon!, size: iconSize),
            Gap(iconGap),
            _label(),
          ],
        ),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: _textButtonStyle(context),
      child: _label(),
    );
  }

  Widget _buildOutlined(BuildContext context) {
    final hasIcon = iconWidget != null || icon != null || isLoading;
    if (hasIcon) {
      return OutlinedButton(
        onPressed: isLoading ? () {} : onPressed,
        style: _outlinedStyle(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              _buildSpinner(context)
            else if (iconWidget != null)
              iconWidget!
            else
              Icon(icon!, size: iconSize),
            Gap(iconGap),
            _label(),
          ],
        ),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: _outlinedStyle(context),
      child: _label(),
    );
  }

  ButtonStyle _textButtonStyle(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor ?? BracuPalette.textPrimary(context),
      backgroundColor: backgroundColor,
      splashFactory: NoSplash.splashFactory,
      overlayColor: Colors.transparent,
      enableFeedback: false,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  ButtonStyle _outlinedStyle(BuildContext context) {
    return bracuCompactOutlinedButtonStyle(
      context,
      foregroundColor: foregroundColor ?? BracuPalette.textPrimary(context),
      padding: padding,
      borderRadius: borderRadius,
    );
  }

  Widget _label() {
    return Text(
      label,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
    );
  }
}

class BracuActionCard extends StatelessWidget {
  const BracuActionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.onTap,
    this.borderRadius = 14,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final borderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: 0.18);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 20),
                const Gap(12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const Gap(4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: BracuPalette.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}

class BracuSpinner extends StatefulWidget {
  const BracuSpinner({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 2.2,
    this.icon,
  });

  final double size;
  final Color? color;
  final double strokeWidth;
  final IconData? icon;

  @override
  State<BracuSpinner> createState() => _BracuSpinnerState();
}

class _BracuSpinnerState extends State<BracuSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spinnerChild = widget.icon != null
        ? Icon(widget.icon, size: widget.size, color: widget.color)
        : SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              strokeWidth: widget.strokeWidth,
              valueColor: widget.color != null
                  ? AlwaysStoppedAnimation<Color>(widget.color!)
                  : null,
            ),
          );

    return RotationTransition(turns: _controller, child: spinnerChild);
  }
}

class BracuRefreshButton extends StatelessWidget {
  const BracuRefreshButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    this.color,
    this.icon = Icons.sync_rounded,
  });

  final VoidCallback onPressed;
  final bool isLoading;
  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? BracuPalette.primary;
    return IconButton(
      tooltip: 'Refresh',
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? BracuSpinner(size: 24, color: themeColor, icon: icon)
          : Icon(icon, color: themeColor),
    );
  }
}

InputDecoration bracuInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? prefixText,
  TextStyle? prefixStyle,
  Widget? prefixIcon,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
  bool isDense = true,
  EdgeInsetsGeometry? contentPadding,
  String? counterText,
  double borderRadius = 12,
}) {
  return InputDecoration(
    labelText: labelText,
    labelStyle: TextStyle(color: BracuPalette.textSecondary(context)),
    hintText: hintText,
    hintStyle: TextStyle(
      color: BracuPalette.textSecondary(context).withValues(alpha: 0.5),
      fontSize: 14,
    ),
    prefixText: prefixText,
    prefixStyle: prefixStyle,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    suffixIconConstraints: suffixIconConstraints,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(
        color: BracuPalette.textSecondary(context).withValues(alpha: 0.2),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: const BorderSide(color: BracuPalette.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(
        color: Colors.red.withValues(alpha: 0.5),
        width: 1,
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
    isDense: isDense,
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    counterText: counterText,
  );
}

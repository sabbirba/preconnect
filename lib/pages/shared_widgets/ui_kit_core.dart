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
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      final spinnerColor = foregroundColor ?? BracuPalette.textPrimary(context);
      return _LoadingButton(
        outlined: outlined,
        onPressed: onPressed,
        padding: padding,
        borderRadius: borderRadius,
        backgroundColor: backgroundColor,
        foregroundColor: spinnerColor,
        iconSize: iconSize,
      );
    }

    return outlined ? _buildOutlined(context) : _buildText(context);
  }

  Widget _buildText(BuildContext context) {
    if (iconWidget != null) {
      return TextButton.icon(
        onPressed: onPressed,
        style: _textButtonStyle(context),
        icon: iconWidget!,
        label: _label(),
      );
    }

    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        style: _textButtonStyle(context),
        icon: Icon(icon, size: iconSize),
        label: _label(),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: _textButtonStyle(context),
      child: _label(),
    );
  }

  Widget _buildOutlined(BuildContext context) {
    if (iconWidget != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: iconWidget!,
        label: _label(),
        style: _outlinedStyle(context),
      );
    }

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        label: _label(),
        style: _outlinedStyle(context),
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
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
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
    return Text(label, style: TextStyle(fontSize: fontSize));
  }
}

class BracuActionCard extends StatelessWidget {
  const BracuActionCard({
    super.key,
    required this.title,
    this.leadingIcon,
    this.trailing,
    this.onTap,
    this.borderRadius = 14,
  });

  final String title;
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
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: BracuPalette.textSecondary(context),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton({
    required this.outlined,
    required this.onPressed,
    required this.padding,
    required this.borderRadius,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.iconSize,
  });

  final bool outlined;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color foregroundColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: iconSize,
      height: iconSize,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
      ),
    );

    if (!outlined) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          enableFeedback: false,
          padding: padding,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: spinner,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: bracuCompactOutlinedButtonStyle(
        context,
        padding: padding,
        borderRadius: borderRadius,
      ),
      child: spinner,
    );
  }
}

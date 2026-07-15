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
    return BracuSpinner(size: iconSize, color: spinnerColor, strokeWidth: 2.2);
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

class BracuLocationPermissionBanner extends StatefulWidget {
  const BracuLocationPermissionBanner({super.key, required this.onFixed});

  final VoidCallback onFixed;

  @override
  State<BracuLocationPermissionBanner> createState() =>
      _BracuLocationPermissionBannerState();
}

class _BracuLocationPermissionBannerState
    extends State<BracuLocationPermissionBanner>
    with WidgetsBindingObserver {
  bool _needsSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSetup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSetup();
    }
  }

  Future<void> _checkSetup() async {
    if (!AndroidNetworkAssist.isSupported) return;
    final hasPermission = await Permission.locationWhenInUse.status.isGranted;
    final gpsEnabled = await AndroidNetworkAssist.isLocationServiceEnabled();
    final needs = !hasPermission || !gpsEnabled;
    if (needs != _needsSetup && mounted) {
      setState(() {
        _needsSetup = needs;
      });
    }
  }

  Future<void> _fix() async {
    if (!AndroidNetworkAssist.isSupported) return;
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        await openAppSettings();
        return;
      }
    }
    final gpsEnabled = await AndroidNetworkAssist.isLocationServiceEnabled();
    if (!gpsEnabled) {
      await AndroidNetworkAssist.openLocationSettings();
      return;
    }
    widget.onFixed();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsSetup) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BracuPalette.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Needs location access and services to detect Wi-Fi.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BracuPalette.textSecondary(context),
              ),
            ),
          ),
          const Gap(10),
          BracuActionButton(
            onPressed: _fix,
            outlined: false,
            borderRadius: 4,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            label: 'Fix',
          ),
        ],
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
  });

  final double size;
  final Color? color;
  final double strokeWidth;

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
    return RotationTransition(
      turns: _controller,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          strokeWidth: widget.strokeWidth,
          valueColor: widget.color != null
              ? AlwaysStoppedAnimation<Color>(widget.color!)
              : null,
        ),
      ),
    );
  }
}

class BracuRefreshButton extends StatelessWidget {
  const BracuRefreshButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    this.color,
  });

  final VoidCallback onPressed;
  final bool isLoading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? BracuPalette.primary;
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: BracuSpinner(size: 20, color: themeColor, strokeWidth: 2.2),
      );
    }
    return IconButton(
      tooltip: 'Refresh',
      onPressed: onPressed,
      icon: Icon(Icons.refresh_rounded, color: themeColor),
    );
  }
}

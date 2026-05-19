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

    if (!outlined) {
      if (icon != null) {
        return TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: iconSize),
          label: Text(label, style: TextStyle(fontSize: fontSize)),
          style: TextButton.styleFrom(
            foregroundColor:
                foregroundColor ?? BracuPalette.textPrimary(context),
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
        );
      }

      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
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
        ),
        child: Text(label, style: TextStyle(fontSize: fontSize)),
      );
    }

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        label: Text(label, style: TextStyle(fontSize: fontSize)),
        style: bracuCompactOutlinedButtonStyle(
          context,
          foregroundColor: foregroundColor ?? BracuPalette.textPrimary(context),
          padding: padding,
          borderRadius: borderRadius,
        ),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: bracuCompactOutlinedButtonStyle(
        context,
        foregroundColor: foregroundColor ?? BracuPalette.textPrimary(context),
        padding: padding,
        borderRadius: borderRadius,
      ),
      child: Text(label, style: TextStyle(fontSize: fontSize)),
    );
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor),
          ),
          child: ListTile(
            leading: leadingIcon == null ? null : Icon(leadingIcon, size: 20),
            title: Text(title),
            trailing:
                trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: BracuPalette.textSecondary(context),
                ),
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

Future<T?> showBracuBottomSheet<T>(
  BuildContext context, {
  required String title,
  ValueListenable<String>? liveTitle,
  String? subtitle,
  List<Widget> actions = const <Widget>[],
  double initialChildSize = 0.80,
  required Widget Function(
    BuildContext sheetContext,
    Color textPrimary,
    Color textSecondary,
  )
  builder,
}) {
  return showBracuCustomBottomSheet<T>(
    context: context,
    backgroundColor: BracuPalette.card(context),
    clipBehavior: Clip.antiAlias,
    initialChildSize: initialChildSize,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    minChildSize: 0.12,
    maxChildSize: 0.98,
    builder: (sheetContext) {
      final textPrimary = BracuPalette.textPrimary(sheetContext);
      final textSecondary = BracuPalette.textSecondary(sheetContext);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textSecondary.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (liveTitle == null)
                          Text(
                            title,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        else
                          ValueListenableBuilder<String>(
                            valueListenable: liveTitle,
                            builder: (context, value, _) {
                              return Text(
                                value,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: Icon(Icons.close_rounded, color: textSecondary),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: builder(sheetContext, textPrimary, textSecondary),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<T?> showBracuCustomBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  bool isScrollControlled = true,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  bool draggable = true,
  double initialChildSize = 0.80,
  double minChildSize = 0.12,
  double maxChildSize = 0.96,
  bool closeOnMinExtent = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    clipBehavior: clipBehavior,
    shape: shape,
    builder: (sheetContext) {
      if (!draggable || !isScrollControlled) {
        return Builder(builder: (innerContext) => builder(innerContext));
      }

      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final minVisibleSheetHeight = switch (defaultTargetPlatform) {
        TargetPlatform.macOS => 112.0,
        TargetPlatform.linux => 112.0,
        TargetPlatform.windows => 112.0,
        _ => 88.0,
      };
      final platformMinSize = (minVisibleSheetHeight / screenHeight).clamp(
        0.10,
        0.40,
      );
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Builder(
          builder: (_) {
            final maxSize = maxChildSize.clamp(0.40, 0.99);
            final minSize = math
                .max(minChildSize, platformMinSize)
                .clamp(0.10, maxSize);
            final initialSize = initialChildSize.clamp(minSize, maxSize);
            var dismissed = false;
            return NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                if (!closeOnMinExtent || dismissed) return false;
                if (notification.extent <= minSize + 0.005) {
                  dismissed = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                  });
                }
                return false;
              },
              child: DraggableScrollableSheet(
                initialChildSize: initialSize,
                minChildSize: minSize,
                maxChildSize: maxSize,
                expand: false,
                builder: (context, scrollController) {
                  return _BracuBottomSheetControllerScope(
                    controller: scrollController,
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: Builder(
                        builder: (innerContext) => builder(innerContext),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    },
  );
}

ScrollController? bracuBottomSheetScrollController(BuildContext context) {
  final scoped = _BracuBottomSheetControllerScope.maybeOf(context);
  return scoped ?? PrimaryScrollController.maybeOf(context);
}

Widget bracuBottomSheetSurface(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(12, 4, 12, 12),
  double radius = 26,
}) {
  return SafeArea(
    top: false,
    child: Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(color: BracuPalette.card(context), child: child),
      ),
    ),
  );
}

class _BracuBottomSheetControllerScope extends InheritedWidget {
  const _BracuBottomSheetControllerScope({
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_BracuBottomSheetControllerScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(_BracuBottomSheetControllerScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

Future<bool> showBracuConfirmationDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  Color confirmColor = BracuPalette.primary,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BracuPalette.card(dialogContext),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: confirmColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(dialogContext),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  color: BracuPalette.textSecondary(dialogContext),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: bracuOutlinedButtonStyle(
                        dialogContext,
                        foregroundColor: confirmColor,
                        borderColor: confirmColor.withValues(alpha: 0.6),
                        borderRadius: 12,
                      ),
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: bracuOutlinedButtonStyle(
                        dialogContext,
                        foregroundColor: confirmColor,
                        borderColor: confirmColor.withValues(alpha: 0.6),
                        borderRadius: 12,
                      ),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed == true;
}

Future<bool> showBracuConfirmationWithActionDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  Color confirmColor = BracuPalette.primary,
  required Future<void> Function() onConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    barrierDismissible: false,
    builder: (dialogContext) => _BracuConfirmationActionDialog(
      icon: icon,
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      onConfirm: onConfirm,
    ),
  );
  return result == true;
}

class _BracuConfirmationActionDialog extends StatefulWidget {
  const _BracuConfirmationActionDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirm,
  });

  final IconData icon;
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final Color confirmColor;
  final Future<void> Function() onConfirm;

  @override
  State<_BracuConfirmationActionDialog> createState() =>
      _BracuConfirmationActionDialogState();
}

class _BracuConfirmationActionDialogState
    extends State<_BracuConfirmationActionDialog> {
  bool _isLoading = false;
  static const Duration _minLoadingDuration = Duration(milliseconds: 300);

  Future<void> _handleConfirm() async {
    if (_isLoading) return;
    final startedAt = DateTime.now();
    setState(() {
      _isLoading = true;
    });
    try {
      await widget.onConfirm();
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minLoadingDuration) {
        await Future<void>.delayed(_minLoadingDuration - elapsed);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BracuPalette.card(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, color: widget.confirmColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: BracuActionButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(false),
                      outlined: true,
                      label: widget.cancelLabel,
                      borderRadius: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BracuActionButton(
                      onPressed: _isLoading ? null : _handleConfirm,
                      outlined: true,
                      isLoading: _isLoading,
                      label: widget.confirmLabel,
                      foregroundColor: widget.confirmColor,
                      backgroundColor: Colors.transparent,
                      borderRadius: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      iconSize: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showBracuSelectSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<BracuSelectOption<T>> options,
  T? selectedValue,
}) {
  return showBracuBottomSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    builder: (sheetContext, textPrimary, textSecondary) {
      return ListView.separated(
        shrinkWrap: true,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option.value == selectedValue;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.of(sheetContext).pop(option.value),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? BracuPalette.primary.withValues(alpha: 0.12)
                      : BracuPalette.card(sheetContext).withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? BracuPalette.primary.withValues(alpha: 0.70)
                        : textSecondary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    if (option.showLeadingIcon) ...[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: selected
                              ? BracuPalette.primary.withValues(alpha: 0.14)
                              : textSecondary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          option.icon ??
                              (selected
                                  ? Icons.check_rounded
                                  : Icons.tune_rounded),
                          size: 18,
                          color: selected
                              ? BracuPalette.primary
                              : textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (option.subtitle != null &&
                              option.subtitle!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              option.subtitle!.trim(),
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      size: selected ? 20 : 18,
                      color: selected
                          ? BracuPalette.primary
                          : textSecondary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<T?> showBracuSelectDropdown<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<BracuSelectOption<T>> options,
  T? selectedValue,
  double optionFontSize = 14,
  EdgeInsetsGeometry optionPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  ),
}) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (renderBox == null || overlay == null) {
    return showBracuSelectSheet<T>(
      context,
      title: title ?? 'Select Option',
      subtitle: subtitle,
      options: options,
      selectedValue: selectedValue,
    );
  }

  final target = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
  final textPrimary = BracuPalette.textPrimary(context);
  final cardColor = BracuPalette.card(context);
  final menuTop = target.dy + renderBox.size.height + 6;
  final maxWidth = overlay.size.width - 24;
  final estimatedWidth = options.fold<double>(
    88,
    (current, option) => math.max(current, 26 + (option.label.length * 10)),
  );
  final menuWidth = estimatedWidth.clamp(88, maxWidth);
  final menuLeft = math.min(target.dx, overlay.size.width - menuWidth - 12);

  return showGeneralDialog<T>(
    context: context,
    barrierLabel: 'Dismiss',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: options.map((option) {
                      final selected = option.value == selectedValue;
                      return InkWell(
                        onTap: () =>
                            Navigator.of(dialogContext).pop(option.value),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: optionPadding,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                option.label,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: optionFontSize,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: BracuPalette.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

class BracuSelectChip extends StatelessWidget {
  const BracuSelectChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
    this.compact = false,
    this.borderRadius = 18,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool compact;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final primaryColor = selected ? BracuPalette.primary : textSecondary;
    final backgroundColor = compact
        ? (selected
              ? BracuPalette.primary.withValues(alpha: 0.14)
              : BracuPalette.card(context).withValues(alpha: 0.94))
        : BracuPalette.card(context).withValues(alpha: 0.94);
    final borderColor = selected
        ? BracuPalette.primary.withValues(alpha: compact ? 0.45 : 0.70)
        : textSecondary.withValues(alpha: 0.26);
    final horizontalPadding = compact ? 11.0 : 14.0;
    final verticalPadding = compact ? 8.0 : 9.0;
    final resolvedRadius = compact ? 14.0 : borderRadius;
    final labelStyle = TextStyle(
      color: BracuPalette.textPrimary(context),
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(resolvedRadius),
      child: Container(
        margin: compact ? null : const EdgeInsets.only(left: 8),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(resolvedRadius),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 15 : 16, color: primaryColor),
              const SizedBox(width: 6),
            ],
            Text(label, style: labelStyle),
            if (showArrow) ...[
              SizedBox(width: compact ? 4 : 6),
              Icon(
                Icons.expand_more_rounded,
                size: compact ? 16 : 18,
                color: primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BracuSelectDropdownChip<T> extends StatelessWidget {
  const BracuSelectDropdownChip({
    super.key,
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.compact = false,
    this.borderRadius = 18,
    this.showArrow = true,
  });

  final String label;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<BracuSelectOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final bool selected;
  final bool compact;
  final double borderRadius;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (chipContext) => BracuSelectChip(
        label: label,
        icon: icon,
        selected: selected,
        compact: compact,
        borderRadius: borderRadius,
        showArrow: showArrow,
        onTap: () async {
          final value = await showBracuSelectDropdown<T>(
            chipContext,
            title: title,
            subtitle: subtitle,
            options: options,
            selectedValue: selectedValue,
          );
          if (value == null) return;
          onSelected(value);
        },
      ),
    );
  }
}

class BracuNotificationsIconButton extends StatefulWidget {
  const BracuNotificationsIconButton({
    super.key,
    required this.onTap,
    this.iconSize = 20,
    this.padding = 7,
  });

  final VoidCallback onTap;
  final double iconSize;
  final double padding;

  @override
  State<BracuNotificationsIconButton> createState() =>
      _BracuNotificationsIconButtonState();
}

class _BracuNotificationsIconButtonState
    extends State<BracuNotificationsIconButton>
    with RefreshBusState {
  late Future<int> _future;
  int? _cachedCount;
  static const String _cachedUnreadCountKey = 'notifications_unread_count_v1';

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedCount());
    _future = NotificationService().getTotalUnreadCount();
    unawaited(_future.then(_persistCount));
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted || !isRefreshingFrom('notifications')) return;
    setState(() {
      _future = NotificationService().getTotalUnreadCount();
    });
    unawaited(_future.then(_persistCount));
  }

  Future<void> _loadCachedCount() async {
    try {
      final count = await AppStorage.instance.getInt(_cachedUnreadCountKey);
      if (!mounted) return;
      setState(() {
        _cachedCount = count;
      });
    } catch (_) {}
  }

  Future<void> _persistCount(int count) async {
    try {
      await AppStorage.instance.setInt(_cachedUnreadCountKey, count);
      if (!mounted) return;
      setState(() {
        _cachedCount = count;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _future,
      builder: (context, snapshot) {
        final newCount = snapshot.data ?? _cachedCount ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(widget.padding),
                child: Icon(
                  Icons.notifications_outlined,
                  size: widget.iconSize,
                  color: BracuPalette.primary,
                ),
              ),
            ),
            if (newCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD63B3B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    newCount > 9 ? '9+' : '$newCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class BracuSearchField extends StatelessWidget {
  const BracuSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.query = '',
    this.onClear,
    this.autofocus = false,
    this.borderRadius = 12,
    this.contentPadding,
    this.keySuffix,
  });

  final TextEditingController controller;
  final String hintText;
  final String query;
  final VoidCallback? onClear;
  final bool autofocus;
  final double borderRadius;
  final EdgeInsetsGeometry? contentPadding;
  final String? keySuffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hintColor = scheme.onSurface.withValues(alpha: 0.64);
    final textColor = scheme.onSurface;
    final borderColor = scheme.onSurface.withValues(alpha: 0.24);
    return TextField(
      key: keySuffix == null
          ? null
          : ValueKey<String>(
              'bracu-search-$keySuffix-${Theme.of(context).brightness.name}',
            ),
      controller: controller,
      autofocus: autofocus,
      style: TextStyle(color: textColor),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.search, color: hintColor),
        suffixIcon: query.trim().isEmpty
            ? null
            : IconButton(
                onPressed: onClear ?? controller.clear,
                icon: Icon(Icons.close, color: hintColor),
              ),
        isDense: true,
        contentPadding: contentPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
    );
  }
}

String formatSectionBadge(String? sectionName) {
  if (sectionName == null) return '?';
  final trimmed = sectionName.trim();
  if (trimmed.isEmpty) return '?';
  final match = RegExp(r'\d+').firstMatch(trimmed);
  if (match == null) return '?';
  final number = int.tryParse(match.group(0)!);
  if (number == null) return match.group(0)!.padLeft(2, '0');
  return number.toString().padLeft(2, '0');
}

const EdgeInsets kBracuPageListPadding = EdgeInsets.fromLTRB(20, 8, 20, 28);

({double itemWidth, double spacing}) quickAccessGridLayout(
  double maxWidth, {
  int targetColumns = 4,
  double minItemWidth = 72.0,
}) {
  const maxSpacing = 12.0;
  const minSpacing = 4.0;

  for (var spacing = maxSpacing; spacing >= minSpacing; spacing -= 1) {
    final width = (maxWidth - spacing * (targetColumns - 1)) / targetColumns;
    if (width >= minItemWidth) {
      return (itemWidth: width, spacing: spacing);
    }
  }

  final fallbackWidth =
      (maxWidth - minSpacing * (targetColumns - 1)) / targetColumns;
  return (
    itemWidth: fallbackWidth.clamp(60.0, double.infinity),
    spacing: minSpacing,
  );
}

class BracuRefreshList extends StatefulWidget {
  const BracuRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.controller,
    this.padding = kBracuPageListPadding,
    this.showScrollTopButton = true,
  });

  final RefreshCallback onRefresh;
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets padding;
  final bool showScrollTopButton;

  @override
  State<BracuRefreshList> createState() => _BracuRefreshListState();
}

class _BracuRefreshListState extends State<BracuRefreshList> {
  ScrollController? _internalController;
  bool _showScrollTop = false;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant BracuRefreshList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onScroll);
    _internalController?.removeListener(_onScroll);
    if (oldWidget.controller == null && widget.controller != null) {
      _internalController?.dispose();
      _internalController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _internalController = ScrollController();
    }
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _internalController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final shouldShow = _controller.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            children: widget.children,
          ),
        ),
        if (widget.showScrollTopButton)
          _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class BracuRefreshListBuilder extends StatefulWidget {
  const BracuRefreshListBuilder({
    super.key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding = kBracuPageListPadding,
  });

  final RefreshCallback onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<BracuRefreshListBuilder> createState() =>
      _BracuRefreshListBuilderState();
}

class _BracuRefreshListBuilderState extends State<BracuRefreshListBuilder> {
  ScrollController? _internalController;
  bool _showScrollTop = false;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant BracuRefreshListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onScroll);
    _internalController?.removeListener(_onScroll);
    if (oldWidget.controller == null && widget.controller != null) {
      _internalController?.dispose();
      _internalController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _internalController = ScrollController();
    }
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _internalController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final shouldShow = _controller.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.builder(
            controller: _controller,
            padding: widget.padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
        ),
        _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class BracuRefreshPlaceholder extends StatelessWidget {
  const BracuRefreshPlaceholder({
    super.key,
    required this.onRefresh,
    required this.child,
    this.topSpacing = 160,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return BracuRefreshList(
      onRefresh: onRefresh,
      children: [
        SizedBox(height: topSpacing),
        child,
      ],
    );
  }
}

Widget buildRefreshLoadingState({
  required RefreshCallback onRefresh,
  String label = '',
  double topSpacing = 160,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: const BracuLoading(),
  );
}

Widget buildRefreshErrorState({
  required RefreshCallback onRefresh,
  required Object? error,
  double topSpacing = 160,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: BracuEmptyState(message: 'Error: $error'),
  );
}

Widget buildRefreshEmptyState({
  required RefreshCallback onRefresh,
  required String message,
  double topSpacing = 160,
}) {
  return BracuRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: BracuEmptyState(message: message),
  );
}

class BracuRefreshScroll extends StatefulWidget {
  const BracuRefreshScroll({
    super.key,
    required this.onRefresh,
    required this.child,
    this.padding = kBracuPageListPadding,
    this.showScrollTopButton = true,
    this.controller,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final EdgeInsets padding;
  final bool showScrollTopButton;
  final ScrollController? controller;

  @override
  State<BracuRefreshScroll> createState() => _BracuRefreshScrollState();
}

class _BracuRefreshScrollState extends State<BracuRefreshScroll> {
  ScrollController? _controller;
  bool _showScrollTop = false;

  ScrollController get _effectiveController =>
      widget.controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = ScrollController();
      _controller!.addListener(_onScroll);
    } else {
      widget.controller!.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    final controller = widget.controller ?? _controller;
    controller?.removeListener(_onScroll);
    _controller?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_effectiveController.hasClients) return;
    final shouldShow = _effectiveController.offset > 360;
    if (shouldShow == _showScrollTop) return;
    setState(() {
      _showScrollTop = shouldShow;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_effectiveController.hasClients) return;
    await _effectiveController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: SingleChildScrollView(
            controller: _effectiveController,
            padding: widget.padding,
            physics: const AlwaysScrollableScrollPhysics(),
            child: widget.child,
          ),
        ),
        if (widget.showScrollTopButton)
          _BracuScrollTopButton(visible: _showScrollTop, onTap: _scrollToTop),
      ],
    );
  }
}

class _BracuScrollTopButton extends StatelessWidget {
  const _BracuScrollTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16 + MediaQuery.of(context).padding.bottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: BracuPalette.textPrimary(context),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BracuPalette {
  static const Color bgTopLight = Color(0xFFEAF4FF);
  static const Color bgBottomLight = Color(0xFFF3FFF4);
  static const Color primary = Color(0xFF1E6BE3);
  static const Color accent = Color(0xFF22B573);
  static const Color info = Color(0xFF2C9DFF);
  static const Color warning = Color(0xFFEF6C35);
  static const Color favorite = Color(0xFFFFA726);
  static const Color danger = Color(0xFFD63B3B);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Colors.black;

  static bool _isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color bgTop(BuildContext context) {
    return _isDark(context) ? Colors.black : bgTopLight;
  }

  static Color bgBottom(BuildContext context) {
    return _isDark(context) ? Colors.black : bgBottomLight;
  }

  static Color card(BuildContext context) {
    return _isDark(context) ? cardDark : cardLight;
  }

  static Color textPrimary(BuildContext context) {
    return _isDark(context) ? Colors.white : Colors.black87;
  }

  static Color textSecondary(BuildContext context) {
    return _isDark(context) ? Colors.white70 : Colors.black54;
  }
}

class BracuPageScaffold extends StatefulWidget {
  const BracuPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    required this.body,
    this.actions = const [],
    this.showMenu = false,
    this.showBack = true,
    this.onHeaderTap,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;

  @override
  State<BracuPageScaffold> createState() => _BracuPageScaffoldState();
}

class _BracuPageScaffoldState extends State<BracuPageScaffold> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
    return ValueListenableBuilder(
      valueListenable: HomeCardPreferences.decorationNotifier,
      builder: (BuildContext context, enabled, Widget? child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ValueListenableBuilder(
            valueListenable: HomeCardPreferences.decorationNotifier,
            builder: (context, decorationsEnabled, child) {
              return Container(
                decoration: decorationsEnabled
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            BracuPalette.bgTop(context),
                            BracuPalette.bgBottom(context),
                          ],
                        ),
                      )
                    : null,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlayStyle,
                  child: Material(
                    type: MaterialType.transparency,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          if (enabled)
                            Positioned(
                              top: -70,
                              right: -60,
                              child: DecorBlob(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                size: 200,
                              ),
                            ),
                          if (enabled)
                            Positioned(
                              bottom: -80,
                              left: -70,
                              child: DecorBlob(
                                color: BracuPalette.accent.withValues(
                                  alpha: 0.10,
                                ),
                                size: 220,
                              ),
                            ),
                          Column(
                            children: [
                              Padding(
                                padding: widget.showBack
                                    ? const EdgeInsets.fromLTRB(6, 12, 20, 8)
                                    : const EdgeInsets.fromLTRB(20, 12, 20, 8),
                                child: _PageHeader(
                                  title: widget.title,
                                  subtitle: widget.subtitle,
                                  icon: widget.icon,
                                  actions: widget.actions,
                                  showMenu: widget.showMenu,
                                  showBack: widget.showBack,
                                  onHeaderTap: widget.onHeaderTap,
                                ),
                              ),
                              Expanded(child: widget.body),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.showMenu,
    required this.showBack,
    this.onHeaderTap,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final bool showMenu;
  final bool showBack;
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final canPop = navigator?.canPop() ?? false;
    final backScope = BracuBackScope.maybeOf(context);
    final canScopeBack = backScope?.canGoBack ?? false;
    final hasBack = showBack && (canPop || canScopeBack);
    final row = Row(
      children: [
        if (showMenu) const SizedBox(width: 0, height: 0),
        if (hasBack)
          Transform.translate(
            offset: const Offset(-2, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (canPop && navigator != null) {
                  navigator.maybePop();
                  return;
                }
                backScope?.onBack();
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
        ...actions,
      ],
    );
    if (onHeaderTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onHeaderTap,
      child: row,
    );
  }
}

class BracuCard extends StatelessWidget {
  const BracuCard({
    super.key,
    required this.child,
    this.isHighlighted = false,
    this.highlightColor,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final bool isHighlighted;
  final Color? highlightColor;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final highlight = highlightColor ?? BracuPalette.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorderColor = BracuPalette.textSecondary(
      context,
    ).withValues(alpha: isDark ? 0.22 : 0.16);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? BracuPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? highlight.withValues(alpha: isDark ? 0.7 : 0.9)
              : baseBorderColor,
          width: isHighlighted ? 1.6 : 1,
        ),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const []
            : [
                BoxShadow(
                  color: isHighlighted
                      ? highlight.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.06),
                  blurRadius: isHighlighted ? 20 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

class BracuSectionTitle extends StatelessWidget {
  const BracuSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BracuPalette.textPrimary(context),
      ),
    );
  }
}

class BracuLoading extends StatelessWidget {
  const BracuLoading({super.key, this.itemCount = 3, this.compact});

  final int itemCount;
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
  }
}

class BracuSkeletonList extends StatelessWidget {
  const BracuSkeletonList({
    super.key,
    this.itemCount = 3,
    this.compact = false,
    this.showLabel = false,
    this.label = '',
  });

  final int itemCount;
  final bool compact;
  final bool showLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class BracuSkeletonGrid extends StatelessWidget {
  const BracuSkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 3,
    this.spacing = 10,
    this.itemHeight = 72,
  });

  final int itemCount;
  final int crossAxisCount;
  final double spacing;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class BracuMetricGridData {
  const BracuMetricGridData({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
}

class BracuMetricGrid extends StatelessWidget {
  const BracuMetricGrid({super.key, required this.items});

  final List<BracuMetricGridData> items;

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    if (count == 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var index = 0; index < count; index++) ...[
          Expanded(child: _BracuMetricTile(data: items[index])),
        ],
      ],
    );
  }
}

class _BracuMetricTile extends StatelessWidget {
  const _BracuMetricTile({required this.data});

  final BracuMetricGridData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, color: BracuPalette.primary, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            data.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class BracuEmptyState extends StatelessWidget {
  const BracuEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: BracuPalette.textSecondary(context)),
      ),
    );
  }
}

class DecorBlob extends StatelessWidget {
  const DecorBlob({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }
}

class BracuBackScope extends InheritedWidget {
  const BracuBackScope({
    super.key,
    required this.canGoBack,
    required this.onBack,
    required super.child,
  });

  final bool canGoBack;
  final VoidCallback onBack;

  static BracuBackScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BracuBackScope>();
  }

  @override
  bool updateShouldNotify(BracuBackScope oldWidget) {
    return canGoBack != oldWidget.canGoBack;
  }
}

class SimpleProgressBar extends StatelessWidget {
  const SimpleProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.backgroundAlpha = 0.12,
  });

  final double value;
  final Color color;
  final double height;
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: color.withValues(alpha: backgroundAlpha),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class SectionBadge extends StatelessWidget {
  const SectionBadge({
    super.key,
    required this.label,
    required this.color,
    this.size = 40,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.backgroundAlpha = 0.12,
    this.borderRadius = 12,
  });

  final String label;
  final Color color;
  final double size;
  final double fontSize;
  final FontWeight fontWeight;
  final double backgroundAlpha;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final normalized = label.trim();
    final displayLabel =
        normalized.isEmpty ||
            normalized == '--' ||
            normalized == '-' ||
            normalized.toUpperCase() == 'N/A'
        ? '?'
        : normalized;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        displayLabel,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

class ShowMoreButton extends StatelessWidget {
  const ShowMoreButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton(
        onPressed: onPressed,
        style: bracuOutlinedButtonStyle(
          context,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          borderRadius: 16,
        ),
        child: Text(
          'Show More',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: BracuPalette.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({
    super.key,
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? Icon(icon, color: color, size: 22)
                  : Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendActionCard extends StatelessWidget {
  const FriendActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.width,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 10.5, color: textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

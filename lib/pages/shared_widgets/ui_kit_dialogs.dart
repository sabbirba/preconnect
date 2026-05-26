part of 'package:preconnect/pages/ui_kit.dart';

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
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: textSecondary.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 6),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 215, maxHeight: 280),
                  child: Material(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(999),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: false,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final selected = option.value == selectedValue;

                        return InkWell(
                          onTap: () =>
                              Navigator.of(dialogContext).pop(option.value),
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
                      },
                    ),
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

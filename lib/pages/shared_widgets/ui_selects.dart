part of 'package:preconnect/pages/ui_kit.dart';

class BracuSelectChip extends StatelessWidget {
  const BracuSelectChip({
    super.key,
    this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.showArrow = true,
    this.compact = false,
    this.borderRadius = 18,
    this.showBorder = true,
  });

  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool compact;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final primaryColor = selected ? BracuPalette.primary : textSecondary;
    final backgroundColor = Colors.transparent;
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
          border: showBorder ? Border.all(color: borderColor) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: label == null ? (compact ? 22 : 24) : (compact ? 15 : 16),
                color: primaryColor,
              ),
              if (label != null || showArrow) const Gap(6),
            ],
            if (label != null) Text(label!, style: labelStyle),
            if (showArrow) ...[
              if (label != null && icon == null) Gap(compact ? 4 : 6),
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
      _future = NotificationService().getTotalUnreadCount(forceRefresh: true);
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
        final bellIcon = newCount > 0
            ? Icons.notifications
            : Icons.notifications_outlined;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(widget.padding),
                child: Icon(
                  bellIcon,
                  size: widget.iconSize,
                  color: BracuPalette.primary,
                ),
              ),
            ),
            if (newCount > 0)
              const Positioned(
                top: 4,
                right: 4,
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BracuPalette.danger,
                      shape: BoxShape.circle,
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

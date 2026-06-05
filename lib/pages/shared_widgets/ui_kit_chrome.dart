part of 'package:preconnect/pages/ui_kit.dart';

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
      builder: (BuildContext context, decorationsEnabled, Widget? child) {
        final enabled = decorationsEnabled == true;
        final baseColor = Theme.of(context).scaffoldBackgroundColor;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: enabled
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
                      : BoxDecoration(color: baseColor),
                ),
              ),
              AnnotatedRegion<SystemUiOverlayStyle>(
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
            ],
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
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? highlight.withValues(alpha: isDark ? 0.7 : 0.9)
              : baseBorderColor,
          width: isHighlighted ? 1.6 : 1,
        ),
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
    final displayLabel = formatSectionBadge(label);
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

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  static ShimmerState? of(BuildContext context) {
    return context.findAncestorStateOfType<ShimmerState>();
  }

  @override
  State<Shimmer> createState() => ShimmerState();
}

class ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Listenable get animation => _controller;
  double get value => _controller.value;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ShimmerContainer extends StatelessWidget {
  const ShimmerContainer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final shimmer = Shimmer.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE0E0E0);
    final highlightColor = isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFF5F5F5);

    if (shimmer == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      );
    }

    return AnimatedBuilder(
      animation: shimmer.animation,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.3, 0.5, 0.7],
              transform: _SlidingGradientTransform(slidePercent: shimmer.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {ui.TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent - 0.5) * 2,
      0.0,
      0.0,
    );
  }
}

part of 'package:preconnect/pages/ui_kit.dart';

String formatSectionBadge(String? sectionName) {
  if (sectionName == null) return '?';
  final trimmed = sectionName.trim();
  if (trimmed.isEmpty) return '?';
  final match = RegExp(r'\d+').firstMatch(trimmed);
  if (match == null) {
    if (trimmed.length > 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed.toUpperCase();
  }
  final number = int.tryParse(match.group(0)!);
  if (number == null) return match.group(0)!.padLeft(2, '0');
  return number.toString().padLeft(2, '0');
}

const EdgeInsets kPageListPadding = EdgeInsets.fromLTRB(14, 8, 14, 28);

({double itemWidth, double spacing}) quickAccessGridLayout(
  double maxWidth, {
  int targetColumns = 4,
  double minItemWidth = 72.0,
}) {
  const maxSpacing = 12.0;
  const minSpacing = 0.0;
  final safeMaxWidth = math.max(0.0, maxWidth - 1.0);

  for (var spacing = maxSpacing; spacing >= minSpacing; spacing -= 1) {
    final width =
        (safeMaxWidth - spacing * (targetColumns - 1)) / targetColumns;
    if (width >= minItemWidth) {
      return (itemWidth: width, spacing: spacing);
    }
  }

  final fallbackWidth =
      (safeMaxWidth - minSpacing * (targetColumns - 1)) / targetColumns;
  return (
    itemWidth: fallbackWidth.clamp(60.0, double.infinity),
    spacing: minSpacing,
  );
}

class AppRefreshList extends StatefulWidget {
  const AppRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.controller,
    this.padding = kPageListPadding,
  });

  final RefreshCallback onRefresh;
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<AppRefreshList> createState() => _AppRefreshListState();
}

class _AppRefreshListState extends State<AppRefreshList> {
  ScrollController? _internalController;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
  }

  @override
  void didUpdateWidget(covariant AppRefreshList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller == null) {
        _internalController ??= ScrollController();
      } else {
        _internalController?.dispose();
        _internalController = null;
      }
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        children: widget.children,
      ),
    );
  }
}

class AppRefreshListBuilder extends StatefulWidget {
  const AppRefreshListBuilder({
    super.key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding = kPageListPadding,
  });

  final RefreshCallback onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  State<AppRefreshListBuilder> createState() => _AppRefreshListBuilderState();
}

class _AppRefreshListBuilderState extends State<AppRefreshListBuilder> {
  ScrollController? _internalController;

  ScrollController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _internalController = widget.controller == null ? ScrollController() : null;
  }

  @override
  void didUpdateWidget(covariant AppRefreshListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    if (oldWidget.controller == null && widget.controller != null) {
      _internalController?.dispose();
      _internalController = null;
    } else if (oldWidget.controller != null && widget.controller == null) {
      _internalController = ScrollController();
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        controller: _controller,
        padding: widget.padding,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}

class AppRefreshPlaceholder extends StatelessWidget {
  const AppRefreshPlaceholder({
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
    return AppRefreshList(
      onRefresh: onRefresh,
      children: [Gap(topSpacing), child],
    );
  }
}

Widget buildRefreshLoadingState({
  required RefreshCallback onRefresh,
  String label = '',
  double topSpacing = 160,
}) {
  return AppRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: const AppLoading(),
  );
}

Widget buildRefreshErrorState({
  required RefreshCallback onRefresh,
  required Object? error,
  double topSpacing = 160,
}) {
  return AppRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: AppEmptyState(message: 'Error: $error'),
  );
}

Widget buildRefreshEmptyState({
  required RefreshCallback onRefresh,
  required String message,
  double topSpacing = 160,
}) {
  return AppRefreshPlaceholder(
    onRefresh: onRefresh,
    topSpacing: topSpacing,
    child: AppEmptyState(message: message),
  );
}

class AppRefreshScroll extends StatefulWidget {
  const AppRefreshScroll({
    super.key,
    required this.onRefresh,
    required this.child,
    this.padding = kPageListPadding,
    this.controller,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  State<AppRefreshScroll> createState() => _AppRefreshScrollState();
}

class _AppRefreshScrollState extends State<AppRefreshScroll> {
  ScrollController? _controller;

  ScrollController get _effectiveController =>
      widget.controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant AppRefreshScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller == null) {
        _controller ??= ScrollController();
      } else {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        controller: _effectiveController,
        padding: widget.padding,
        physics: const AlwaysScrollableScrollPhysics(),
        child: widget.child,
      ),
    );
  }
}

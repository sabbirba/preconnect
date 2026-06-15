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

const EdgeInsets kBracuPageListPadding = EdgeInsets.fromLTRB(20, 8, 20, 28);

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

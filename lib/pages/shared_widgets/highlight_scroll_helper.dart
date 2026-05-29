import 'dart:async';

import 'package:flutter/material.dart';

class HighlightScrollCoordinator {
  HighlightScrollCoordinator({
    required this.scrollController,
    this.alignment = 0.18,
    this.maxRetries = 2,
  });

  final ScrollController scrollController;
  final double alignment;
  final int maxRetries;

  GlobalKey? highlightKey;
  String? _lastTargetToken;
  bool _didScroll = false;
  bool _isRunning = false;

  void resetForTarget(String? targetToken) {
    if (targetToken != null && targetToken != _lastTargetToken) {
      _lastTargetToken = targetToken;
      _didScroll = false;
    }
  }

  void clearHighlightKey() {
    highlightKey = null;
  }

  void markHighlighted(bool isHighlighted) {
    if (isHighlighted) {
      highlightKey ??= GlobalKey();
    }
  }

  void resetScrollState() {
    _didScroll = false;
  }

  Future<void> scrollToTarget({
    required String? targetToken,
    required VoidCallback onRetryBuild,
    int? targetIndex,
    int? itemCount,
  }) async {
    resetForTarget(targetToken);
    if (_didScroll || highlightKey == null || _isRunning) return;

    _isRunning = true;
    try {
      for (var attempt = 0; attempt <= maxRetries; attempt++) {
        await WidgetsBinding.instance.endOfFrame;

        final targetContext = highlightKey?.currentContext;
        if (targetContext != null && targetContext.mounted) {
          Scrollable.ensureVisible(
            targetContext,
            alignment: alignment,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          );
          _didScroll = true;
          return;
        }

        if (attempt == maxRetries) {
          continue;
        }

        if (targetIndex != null &&
            itemCount != null &&
            itemCount > 1 &&
            scrollController.hasClients) {
          final maxScrollExtent = scrollController.position.maxScrollExtent;
          final ratio = (targetIndex / (itemCount - 1)).clamp(0.0, 1.0);
          await scrollController.animateTo(
            maxScrollExtent * ratio,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }

        onRetryBuild();
      }
    } finally {
      _isRunning = false;
    }
  }
}

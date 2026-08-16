import 'package:flutter/material.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

typedef SectionLoader<T> =
    Future<List<Section>> Function(T key, {bool forceRefresh});

class SectionLoadController<T> extends ChangeNotifier {
  SectionLoadController({required this.key, required this.loader});

  final T key;
  final SectionLoader<T> loader;

  bool isLoading = false;
  bool isLoaded = false;
  String? error;
  List<Section> sections = const <Section>[];
  bool _isDisposed = false;

  Future<void> load({bool forceRefresh = false}) async {
    if (_isDisposed || isLoading) return;
    isLoading = true;
    error = null;
    _notify();
    try {
      sections = await loader(key, forceRefresh: forceRefresh);
      isLoaded = true;
    } catch (exception) {
      error = sectionLoadErrorMessage(exception);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class SectionLoadView<T> extends StatelessWidget {
  const SectionLoadView({
    super.key,
    required this.controller,
    required this.errorTitle,
    required this.label,
    required this.emptyMessage,
  });

  final SectionLoadController<T> controller;
  final String errorTitle;
  final String label;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasData = controller.sections.isNotEmpty;
        if (controller.isLoading && !hasData && controller.error == null) {
          return const Center(child: BracuLoading());
        }
        if (controller.error != null && !hasData) {
          return BracuErrorState(
            title: errorTitle,
            message: controller.error ?? '',
            onRetry: () => controller.load(forceRefresh: true),
          );
        }
        return BracuRefreshList(
          onRefresh: () => controller.load(forceRefresh: true),
          children: [
            SectionListCard(
              label: label,
              sections: controller.sections,
              emptyMessage: emptyMessage,
            ),
          ],
        );
      },
    );
  }
}

String sectionLoadErrorMessage(Object error) {
  if (error is StudentPortfolioUnavailableException) return error.toString();
  if (error is ApiException) {
    return switch (error.statusCode) {
      401 => 'Your BRACU session expired. Sign in again and retry.',
      403 => 'This advising information is not available for your account.',
      404 => 'This advising phase is not currently available.',
      >= 500 => 'BRACU Connect is temporarily unavailable. Try again later.',
      _ => 'Could not load advising information. Try again.',
    };
  }
  if (error is FormatException) {
    return 'BRACU Connect returned an unsupported response. Try again later.';
  }
  return 'Could not load advising information. Check your connection and retry.';
}

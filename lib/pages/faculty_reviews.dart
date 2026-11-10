import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/time_utils.dart';

const Map<String, String> _questionLabels = <String, String>{
  'teaching': 'Teaching',
  'grading': 'Fair Grading',
  'recommend': 'Would Recommend',
};

Future<void> showFacultyReviews(
  BuildContext context, {
  required String initial,
  String name = '',
  String roomId = '',
  bool canReview = false,
}) {
  final title = name.isEmpty || name == initial ? initial : '$name ($initial)';
  return showAppBottomSheet<void>(
    context,
    title: title,
    subtitle: 'Faculty Reviews',
    initialChildSize: 0.9,
    builder: (sheetContext, textPrimary, textSecondary) => _ReviewsSheet(
      initial: initial,
      roomId: roomId,
      canReview: canReview,
      scrollController: bottomSheetScrollController(sheetContext),
    ),
  );
}

class FacultyRatingBadge extends StatefulWidget {
  const FacultyRatingBadge({super.key, required this.initial, this.name = ''});

  final String initial;
  final String name;

  @override
  State<FacultyRatingBadge> createState() => _FacultyRatingBadgeState();
}

class _FacultyRatingBadgeState extends State<FacultyRatingBadge> {
  final ChatService _chat = ChatService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_chat.loadFacultyRatings().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, ChatFaculty>>(
      valueListenable: _chat.facultyRatings,
      builder: (context, ratings, _) {
        final faculty = ratings[widget.initial.trim().toUpperCase()];
        final textSecondary = AppPalette.textSecondary(context);
        final label = faculty == null || faculty.reviewCount == 0
            ? 'No reviews yet'
            : faculty.visible
            ? '${faculty.ratings.overall.toStringAsFixed(1)} · '
                  '${_reviewCount(faculty.reviewCount)}'
            : '${_reviewCount(faculty.reviewCount)} · '
                  'shown after ${faculty.minimum}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppActionCard(
            title: 'Student Reviews',
            subtitle: label,
            leadingIcon: Icons.star_outline_rounded,
            trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
            onTap: () => showFacultyReviews(
              context,
              initial: widget.initial,
              name: widget.name,
            ),
          ),
        );
      },
    );
  }
}

String _reviewCount(int count) => count == 1 ? '1 review' : '$count reviews';

class _ReviewsSheet extends StatefulWidget {
  const _ReviewsSheet({
    required this.initial,
    required this.roomId,
    required this.canReview,
    required this.scrollController,
  });

  final String initial;
  final String roomId;
  final bool canReview;
  final ScrollController? scrollController;

  @override
  State<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<_ReviewsSheet> {
  final ChatService _chat = ChatService.instance;
  final TextEditingController _comment = TextEditingController();
  final Map<String, int> _ratings = <String, int>{};
  ChatFacultyReviews? _data;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _chat.loadReviews(
        roomId: widget.roomId,
        initial: widget.initial,
      );
      if (!mounted) return;
      final mine = data.mine;
      setState(() {
        _data = data;
        _error = null;
        if (mine != null) {
          for (final field in ChatRatings.fields) {
            _ratings[field] = mine.ratings[field].round();
          }
          _comment.text = mine.comment;
        }
      });
    } on ChatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Reviews could not be loaded.');
    }
  }

  int get _commentMin => _chat.settings.value.reviewCommentMin;

  bool get _complete =>
      ChatRatings.fields.every((field) => (_ratings[field] ?? 0) > 0) &&
      _comment.text.trim().length >= _commentMin;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _saving = true);
    try {
      await action();
      unawaited(_chat.loadFacultyRatings(force: true));
      if (mounted) showAppSnackBar(context, done);
      await _load();
    } on ChatException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() => _run(
    () => _chat.saveReview(
      widget.roomId,
      Map<String, int>.from(_ratings),
      _comment.text.trim(),
    ),
    'Your review is saved.',
  );

  Future<void> _report(ChatReview review) =>
      _run(() => _chat.reportReview(review.id), 'Reported to the moderators.');

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_error != null) {
      return AppErrorState(
        title: 'Reviews Unavailable',
        message: _error!,
        onRetry: _load,
      );
    }
    if (data == null) return const AppLoading();
    final faculty = data.faculty;
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      children: [
        if (faculty != null) _Summary(faculty: faculty),
        if (widget.canReview) ...[
          const Gap(16),
          AppSectionTitle(
            title: data.mine == null ? 'Your Review' : 'Edit Your Review',
          ),
          const Gap(8),
          for (final field in ChatRatings.fields)
            _StarRow(
              label: _questionLabels[field]!,
              value: _ratings[field] ?? 0,
              onChanged: (value) => setState(() => _ratings[field] = value),
            ),
          const Gap(8),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: appInputDecoration(
              context,
              hintText:
                  'What is this faculty like? At least $_commentMin '
                  'characters, shared anonymously.',
              counterText: '',
            ),
          ),
          const Gap(12),
          AppActionButton(
            label: data.mine == null ? 'Submit Review' : 'Update Review',
            outlined: false,
            backgroundColor: AppPalette.primary,
            foregroundColor: Colors.white,
            onPressed: _complete && !_saving ? _save : null,
          ),
        ],
        if (data.locked) ...[
          const Gap(16),
          const AppSectionTitle(title: 'Comments'),
          const Gap(8),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              widget.canReview
                  ? 'Submit your review to see what your classmates wrote.'
                  : 'Review this faculty from your section chat to see what '
                        'your classmates wrote.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ),
        ],
        if (data.reviews.isNotEmpty) ...[
          const Gap(16),
          const AppSectionTitle(title: 'Comments'),
          const Gap(8),
          for (final review in data.reviews)
            _ReviewCard(
              review: review,
              onReport: review.mine || _saving ? null : () => _report(review),
            ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.faculty});

  final ChatFaculty faculty;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    if (!faculty.visible) {
      return AppCard(
        padding: const EdgeInsets.all(14),
        child: Text(
          faculty.reviewCount == 0
              ? 'No reviews yet. Ratings appear once ${faculty.minimum} '
                    'students from this faculty\'s sections have reviewed.'
              : '${_reviewCount(faculty.reviewCount)} so far. Ratings appear '
                    'once ${faculty.minimum} students have reviewed, so no '
                    'single review can be identified.',
          style: TextStyle(fontSize: 13, height: 1.4, color: textSecondary),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                faculty.ratings.overall.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const Gap(10),
              Text(
                'from ${_reviewCount(faculty.reviewCount)}',
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
            ],
          ),
          const Gap(8),
          for (final field in ChatRatings.fields)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _questionLabels[field]!,
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                  ),
                  _Stars(value: faculty.ratings[field]),
                  const Gap(8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      faculty.ratings[field].toStringAsFixed(1),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value});

  static const double _size = 14;

  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i - 0.25
                ? Icons.star_rounded
                : value >= i - 0.75
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: _size,
            color: AppPalette.primary,
          ),
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ),
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i of 5',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(i),
              icon: Icon(
                i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i <= value
                    ? AppPalette.primary
                    : AppPalette.textSecondary(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.onReport});

  final ChatReview review;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Stars(value: review.ratings.overall),
                const Gap(8),
                Expanded(
                  child: Text(
                    '${review.courseCode} · '
                    '${AppTime.formatDayMonth(review.updated.toLocal())}'
                    '${review.mine ? ' · You' : ''}',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ),
                if (onReport != null)
                  IconButton(
                    tooltip: 'Report',
                    visualDensity: VisualDensity.compact,
                    onPressed: onReport,
                    icon: Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: textSecondary,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 4),
              child: Text(
                review.comment,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

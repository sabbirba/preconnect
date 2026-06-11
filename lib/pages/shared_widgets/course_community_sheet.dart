import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/course_material.dart';
import 'package:preconnect/api/faculty_review.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';

class CourseCommunitySheet extends StatefulWidget {
  const CourseCommunitySheet.forClass({
    super.key,
    required this.courseCode,
    required this.sectionName,
    required this.semesterLabel,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.courseType,
    required this.classSchedule,
    required this.isRamadan,
    this.showActions = true,
  }) : examType = null,
       examDateLabel = null,
       examTimeLabel = null;

  const CourseCommunitySheet.forExam({
    super.key,
    required this.courseCode,
    required this.sectionName,
    required this.semesterLabel,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.courseType,
    required this.examType,
    required this.examDateLabel,
    required this.examTimeLabel,
    this.showActions = true,
  }) : classSchedule = null,
       isRamadan = false;

  final String courseCode;
  final String sectionName;
  final String semesterLabel;
  final String? roomNumber;
  final String? faculties;
  final int? consumedSeat;
  final String? courseType;
  final section.ClassSchedule? classSchedule;
  final bool isRamadan;

  final String? examType;
  final String? examDateLabel;
  final String? examTimeLabel;
  final bool showActions;

  bool get isExamMode => classSchedule == null;

  @override
  State<CourseCommunitySheet> createState() => _CourseCommunitySheetState();
}

class _CourseCommunitySheetState extends State<CourseCommunitySheet> {
  final FacultyReviewService _facultyService = FacultyReviewService();
  final CourseMaterialService _materialService = CourseMaterialService();
  final ProfileService _profileService = ProfileService();
  final TextEditingController _reviewCommentController =
      TextEditingController();
  final TextEditingController _materialLinkController = TextEditingController();
  final TextEditingController _materialTitleController =
      TextEditingController();

  FacultyReviewFeed? _reviewFeed;
  List<CourseMaterialItem> _materials = const <CourseMaterialItem>[];
  bool _busyWriteAction = false;
  bool _showAllReviews = false;
  bool _showAllMaterials = false;
  bool _reviewsLoading = true;
  bool _materialsLoading = true;
  String? _reviewsError;
  String? _materialsError;
  String _currentUserName = '';

  String get _facultyInitial {
    final raw = (widget.faculties ?? '').trim().toUpperCase();
    if (raw.isEmpty) return '';
    final first = raw.split(RegExp(r'[,/\s;|]+')).first.trim();
    final cleaned = first.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned == 'TBA') return '';
    return cleaned;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _reviewCommentController.dispose();
    _materialLinkController.dispose();
    _materialTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait<void>(<Future<void>>[
      _loadReviews(),
      _loadMaterials(),
      _loadCurrentUserName(),
    ]);
  }

  Future<void> _loadCurrentUserName() async {
    try {
      final profile = await _profileService.getProfile();
      final fullName = (profile?['fullName'] ?? '').trim();
      if (!mounted) return;
      setState(() {
        _currentUserName = fullName;
      });
    } catch (_) {}
  }

  Future<void> _loadReviews() async {
    setState(() {
      _reviewsLoading = true;
      _reviewsError = null;
    });
    final initial = _facultyInitial;
    if (initial.isEmpty) {
      setState(() {
        _reviewsError = 'Not available';
      });
      return;
    }
    try {
      final feed = await _facultyService.getFacultyReviews(initial, limit: 20);
      final facultyDetails = _needsFacultyLookup(feed.faculty)
          ? await _facultyService.getFacultyByInitial(initial)
          : null;
      final mergedFaculty = _mergeFacultySummary(
        primary: feed.faculty,
        lookup: facultyDetails,
        fallbackInitial: initial,
      );
      final mergedFeed = FacultyReviewFeed(
        faculty: mergedFaculty,
        reviews: feed.reviews,
        limit: feed.limit,
        offset: feed.offset,
      );
      if (!mounted) return;
      setState(() {
        _reviewFeed = mergedFeed;
      });
    } catch (_) {
      try {
        final facultyDetails = await _facultyService.getFacultyByInitial(
          initial,
        );
        if (!mounted) return;
        if (facultyDetails != null) {
          setState(() {
            _reviewFeed = FacultyReviewFeed(
              faculty: facultyDetails,
              reviews: const <FacultyReviewItem>[],
              limit: 20,
              offset: 0,
            );
            _reviewsError = null;
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _reviewsError = 'Not available';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _reviewsLoading = false;
        });
      }
    }
  }

  FacultySummary _mergeFacultySummary({
    required FacultySummary primary,
    required FacultySummary? lookup,
    required String fallbackInitial,
  }) {
    final source = lookup;
    final initial = (source?.initial ?? '').trim().isNotEmpty
        ? source!.initial
        : (primary.initial.trim().isNotEmpty
              ? primary.initial
              : fallbackInitial);
    final name = (source?.name ?? '').trim().isNotEmpty
        ? source!.name
        : primary.name;
    final email = (source?.email ?? '').trim().isNotEmpty
        ? source!.email
        : primary.email;
    final courses = (source?.courses ?? const <String>[])
        .where((c) => c.trim().isNotEmpty)
        .toList();
    final mergedCourses = courses.isNotEmpty ? courses : primary.courses;
    final stats = primary.stats.reviewsTotal > 0
        ? primary.stats
        : (source?.stats ?? primary.stats);
    return FacultySummary(
      facultyId: (source?.facultyId ?? 0) > 0
          ? source!.facultyId
          : primary.facultyId,
      initial: initial,
      name: name,
      email: email,
      courses: mergedCourses,
      stats: stats,
      reviewSummary: primary.reviewSummary,
      reviewInsights: primary.reviewInsights,
      sourceLabel: primary.sourceLabel,
    );
  }

  Widget _buildCompactLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }

  bool _needsFacultyLookup(FacultySummary faculty) {
    return faculty.name.trim().isEmpty ||
        faculty.courses.isEmpty ||
        faculty.email.trim().isEmpty;
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _materialsLoading = true;
      _materialsError = null;
    });
    try {
      final list = await _materialService.list(
        courseCode: widget.courseCode,
        limit: 20,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _materials = list;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _materialsError = 'Not available';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _materialsLoading = false;
        });
      }
    }
  }

  Future<void> _writeReview() async {
    if (_busyWriteAction) return;
    final initial = _facultyInitial;
    if (initial.isEmpty) {
      showAppSnackBar(
        context,
        'Not available',
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final allReviews = _reviewFeed?.reviews ?? const <FacultyReviewItem>[];
    FacultyReviewItem? myOwnedReview;
    for (final review in allReviews) {
      if (review.reviewId > 0 && review.canDelete == true) {
        myOwnedReview = review;
        break;
      }
    }
    _reviewCommentController.text = myOwnedReview?.comment ?? '';
    int? overall;
    int? teaching;
    int? fairness;
    int? behavior;
    if (myOwnedReview != null) {
      overall = myOwnedReview.overall > 0 ? myOwnedReview.overall : null;
      teaching = myOwnedReview.teaching > 0 ? myOwnedReview.teaching : null;
      fairness = myOwnedReview.fairness > 0 ? myOwnedReview.fairness : null;
      behavior = myOwnedReview.behavior > 0 ? myOwnedReview.behavior : null;
    }

    final result = await showBracuBottomSheet<bool>(
      context,
      title: myOwnedReview == null ? 'Write' : 'Edit',
      builder: (sheetContext, textPrimary, textSecondary) {
        final sheetScroll = bracuBottomSheetScrollController(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget ratingRow(
              String label,
              int? value,
              ValueChanged<int> onChanged,
            ) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ...List<Widget>.generate(5, (index) {
                    final star = index + 1;
                    final selected = value != null && star <= value;
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setSheetState(() => onChanged(star)),
                      icon: Icon(
                        selected ? Icons.star_rounded : Icons.star_border,
                        color: BracuPalette.warning,
                      ),
                    );
                  }),
                ],
              );
            }

            final comment = _reviewCommentController.text.trim();
            final ratingsReady =
                overall != null &&
                teaching != null &&
                fairness != null &&
                behavior != null;
            final canSubmit = ratingsReady && comment.isNotEmpty;

            return SingleChildScrollView(
              controller: sheetScroll,
              child: Column(
                children: [
                  ratingRow('Overall', overall, (v) => overall = v),
                  ratingRow('Teaching', teaching, (v) => teaching = v),
                  ratingRow('Fairness', fairness, (v) => fairness = v),
                  ratingRow('Behavior', behavior, (v) => behavior = v),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reviewCommentController,
                    maxLines: 4,
                    maxLength: 500,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Write your review...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: BracuActionButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          label: 'Cancel',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BracuActionButton(
                          onPressed: canSubmit
                              ? () => Navigator.of(sheetContext).pop(true)
                              : null,
                          isLoading: _busyWriteAction,
                          label: myOwnedReview == null ? 'Submit' : 'Save',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != true) return;
    if (!mounted) return;
    final comment = _reviewCommentController.text.trim();
    if (comment.isEmpty) {
      showAppSnackBar(context, 'Comment is required');
      return;
    }
    if (overall == null ||
        teaching == null ||
        fairness == null ||
        behavior == null) {
      showAppSnackBar(context, 'All star ratings are required');
      return;
    }

    setState(() {
      _busyWriteAction = true;
    });
    try {
      await _facultyService.upsertReview(
        FacultyReviewUpsertInput(
          facultyInitial: initial,
          overall: overall!,
          teaching: teaching!,
          fairness: fairness!,
          behavior: behavior!,
          comment: comment,
        ),
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        myOwnedReview == null ? 'Review submitted' : 'Review saved',
      );
      await _loadReviews();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Review not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<void> _deleteReview(int reviewId) async {
    final deleted = await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete Review?',
      message: 'You can only delete your own review.',
      confirmLabel: 'Delete',
      confirmColor: BracuPalette.danger,
      onConfirm: () => _facultyService.deleteReview(reviewId),
    );
    if (!deleted || !mounted) return;
    showAppSnackBar(context, 'Review deleted');
    await _loadReviews();
  }

  Future<void> _openMaterial(CourseMaterialItem item) async {
    try {
      final parsed = _parseMaterialMeta(item);
      final directLink = parsed.linkUrl;
      if (_isValidHttpUrl(directLink)) {
        await openExternalUrl(context, directLink);
        return;
      }
      final detail = await _materialService.get(
        semester: item.semester,
        courseCode: item.courseCode,
        fileName: item.fileName,
      );
      if (!mounted) return;
      final detailParsed = _parseMaterialMeta(detail.item);
      final detailLink = detailParsed.linkUrl;
      if (_isValidHttpUrl(detailLink)) {
        await openExternalUrl(context, detailLink);
        return;
      }
      if (detail.downloadUrl.isEmpty) {
        showAppSnackBar(context, 'Download URL unavailable');
        return;
      }
      final publicUrl = _materialService.resolvePublicDownloadUrl(
        item: detail.item,
        signedDownloadUrl: detail.downloadUrl,
      );
      await openExternalUrl(context, publicUrl);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Open not available now');
    }
  }

  Future<void> _deleteMaterial(CourseMaterialItem item) async {
    final deleted = await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete Material?',
      message: 'You can only delete your own uploaded material.',
      confirmLabel: 'Delete',
      confirmColor: BracuPalette.danger,
      onConfirm: () => _materialService.delete(
        semester: item.semester,
        courseCode: item.courseCode,
        fileName: item.fileName,
      ),
    );
    if (!deleted || !mounted) return;
    showAppSnackBar(context, 'Material deleted');
    await _loadMaterials();
  }

  String _contentTypeForPath(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.url')) return 'text/uri-list';
    return 'application/octet-stream';
  }

  Future<void> _openAddMaterialSheet() async {
    if (_busyWriteAction) return;
    _materialLinkController.clear();
    _materialTitleController.clear();
    Uint8List? selectedFileBytes;
    String selectedFileName = '';
    bool pickingFile = false;
    bool submitting = false;
    _AddMaterialTab activeTab = _AddMaterialTab.file;
    await showBracuBottomSheet<void>(
      context,
      title: 'Add Material',
      subtitle: 'Choose File or Link',
      builder: (sheetContext, textPrimary, textSecondary) {
        final sheetScroll = bracuBottomSheetScrollController(sheetContext);
        return StatefulBuilder(
          builder: (innerContext, setSheetState) {
            return ListView(
              controller: sheetScroll,
              shrinkWrap: true,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: BracuPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BracuPalette.textSecondary(
                        context,
                      ).withValues(alpha: 0.2),
                    ),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AddTabButton(
                          label: 'File',
                          icon: Icons.upload_file_rounded,
                          selected: activeTab == _AddMaterialTab.file,
                          onTap: () {
                            setSheetState(() {
                              activeTab = _AddMaterialTab.file;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _AddTabButton(
                          label: 'Link',
                          icon: Icons.link_rounded,
                          selected: activeTab == _AddMaterialTab.link,
                          onTap: () {
                            setSheetState(() {
                              activeTab = _AddMaterialTab.link;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activeTab == _AddMaterialTab.file) ...[
                        Text(
                          'Add File',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Upload PDF, DOCX, PPTX, images, .zip and more.',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _materialTitleController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            hintText: 'Lecture 03 Notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: BracuActionButton(
                            onPressed: (pickingFile || submitting)
                                ? null
                                : () async {
                                    setSheetState(() {
                                      pickingFile = true;
                                    });
                                    try {
                                      final XFile? picked = await openFile();
                                      if (!mounted) return;
                                      if (picked == null) {
                                        setSheetState(() {
                                          pickingFile = false;
                                        });
                                        return;
                                      }
                                      final bytes = await picked.readAsBytes();
                                      setSheetState(() {
                                        pickingFile = false;
                                      });
                                      if (bytes.isEmpty) {
                                        if (!mounted) return;
                                        showAppSnackBar(
                                          context,
                                          'Unable to read selected file',
                                        );
                                        return;
                                      }
                                      setSheetState(() {
                                        selectedFileName = picked.name.trim();
                                        selectedFileBytes = bytes;
                                      });
                                    } catch (_) {
                                      setSheetState(() {
                                        pickingFile = false;
                                      });
                                    }
                                  },
                            icon: Icons.upload_file_rounded,
                            label: 'Choose File',
                            isLoading: pickingFile,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Add Link',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Accessible YouTube video/playlist, GitHub repositories, or any web resource.',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _materialLinkController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Link URL',
                            hintText: 'https://youtube.com/...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _materialTitleController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            hintText: 'Lecture 03 Recording',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (activeTab == _AddMaterialTab.file &&
                    selectedFileName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected: $selectedFileName',
                    style: TextStyle(color: textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BracuActionButton(
                        onPressed: (pickingFile || submitting)
                            ? null
                            : () => Navigator.of(sheetContext).pop(),
                        label: 'Cancel',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BracuActionButton(
                        onPressed: (pickingFile || submitting)
                            ? null
                            : () async {
                                if (activeTab == _AddMaterialTab.file) {
                                  if (selectedFileBytes == null ||
                                      selectedFileName.trim().isEmpty) {
                                    showAppSnackBar(
                                      context,
                                      'Choose a file first',
                                    );
                                    return;
                                  }
                                  final customTitle = _materialTitleController
                                      .text
                                      .trim();
                                  if (customTitle.isEmpty) {
                                    showAppSnackBar(
                                      context,
                                      'Title is required',
                                    );
                                    return;
                                  }
                                  setSheetState(() {
                                    submitting = true;
                                  });
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  await _uploadMaterialBytes(
                                    fileName: selectedFileName.trim(),
                                    bytes: selectedFileBytes!,
                                    titleHint: customTitle,
                                    descriptionHint:
                                        'Uploaded from class/exam schedule',
                                    linkUrl: '',
                                  );
                                  return;
                                }

                                final url = _materialLinkController.text.trim();
                                final customTitle = _materialTitleController
                                    .text
                                    .trim();
                                if (customTitle.isEmpty) {
                                  showAppSnackBar(context, 'Title is required');
                                  return;
                                }
                                if (!_isValidHttpUrl(url)) {
                                  showAppSnackBar(
                                    context,
                                    'Enter a valid http or https link',
                                  );
                                  return;
                                }
                                final uri = Uri.parse(url);
                                final fileName = _materialLinkFileName(uri);
                                setSheetState(() {
                                  submitting = true;
                                });
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                                await _saveMaterialLink(
                                  fileName: fileName,
                                  titleHint: customTitle,
                                  descriptionHint:
                                      'Link shared from class/exam schedule',
                                  linkUrl: url,
                                );
                              },
                        icon: activeTab == _AddMaterialTab.file
                            ? Icons.check_circle_outline
                            : Icons.link_rounded,
                        label: 'Submit',
                        isLoading: submitting,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveMaterialLink({
    required String fileName,
    required String titleHint,
    required String descriptionHint,
    required String linkUrl,
  }) async {
    if (_busyWriteAction) return;
    final normalizedName = fileName.trim();
    final normalizedLink = linkUrl.trim();
    if (normalizedName.isEmpty || !_isValidHttpUrl(normalizedLink)) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      final title = titleHint.trim();
      if (title.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'Title is required');
        return;
      }
      await _materialService.finalize(
        CourseMaterialFinalizeInput(
          key: '',
          courseCode: widget.courseCode,
          courseTitle: widget.courseCode,
          semester: widget.semesterLabel,
          title: title,
          description: _materialDescription(
            base: descriptionHint,
            uploaderName: _currentUserName,
            linkUrl: normalizedLink,
          ),
          fileName: normalizedName,
          contentType: 'text/uri-list',
          fileSize: 0,
          externalUrl: normalizedLink,
        ),
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Link added');
      await _loadMaterials();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Link add not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<void> _uploadMaterialBytes({
    required String fileName,
    required Uint8List bytes,
    required String titleHint,
    required String descriptionHint,
    required String linkUrl,
  }) async {
    if (_busyWriteAction) return;
    final normalizedName = fileName.trim();
    if (normalizedName.isEmpty || bytes.isEmpty) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      final contentType = _contentTypeForPath(normalizedName);
      final uploadMeta = await _materialService.createUploadUrl(
        CourseMaterialUploadUrlInput(
          fileName: normalizedName,
          contentType: contentType,
          courseCode: widget.courseCode,
          semester: widget.semesterLabel,
        ),
      );
      await _materialService.uploadToSignedUrl(
        uploadUrl: uploadMeta.uploadUrl,
        contentType: contentType,
        bytes: bytes,
      );
      final title = titleHint.trim();
      if (title.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'Title is required');
        return;
      }
      await _materialService.finalize(
        CourseMaterialFinalizeInput(
          key: uploadMeta.key,
          courseCode: widget.courseCode,
          courseTitle: widget.courseCode,
          semester: widget.semesterLabel,
          title: title,
          description: _materialDescription(
            base: descriptionHint,
            uploaderName: _currentUserName,
            linkUrl: linkUrl,
          ),
          fileName: normalizedName,
          contentType: contentType,
          fileSize: bytes.length,
          externalUrl: linkUrl,
        ),
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        linkUrl.isNotEmpty ? 'Link added' : 'Material uploaded',
      );
      await _loadMaterials();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        linkUrl.isNotEmpty
            ? 'Link add not available now'
            : 'Upload not available now',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  bool _isValidHttpUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return uri.hasAuthority;
  }

  String _materialLinkFileName(Uri uri) {
    final host = uri.host.trim().replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeHost = host.isEmpty ? 'link' : host.toLowerCase();
    return '$safeHost-$ts.url';
  }

  String _materialDescription({
    required String base,
    required String uploaderName,
    required String linkUrl,
  }) {
    final payload = <String, String>{
      if (uploaderName.trim().isNotEmpty) 'uploader': uploaderName.trim(),
      if (linkUrl.trim().isNotEmpty) 'linkUrl': linkUrl.trim(),
    };
    if (payload.isEmpty) return base;
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    return '$base\nPCMETA:$encoded';
  }

  Widget _buildSummaryCard() {
    if (!widget.isExamMode && widget.classSchedule != null) {
      return ScheduleEntryCard(
        sectionName: widget.sectionName,
        courseCode: widget.courseCode,
        schedule: widget.classSchedule!,
        isRamadan: widget.isRamadan,
        roomNumber: widget.roomNumber,
        faculties: widget.faculties,
        consumedSeat: widget.consumedSeat,
        courseType: widget.courseType,
      );
    }
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final roomLabel = (widget.roomNumber ?? '').trim();
    final consumedLabel = (widget.consumedSeat ?? 0) > 0
        ? '(${widget.consumedSeat})'
        : '';
    final examType = (widget.examType ?? '').trim().toLowerCase();
    final badgeColor = examType == 'midterm'
        ? BracuPalette.primary
        : BracuPalette.accent;
    return BracuCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionBadge(
            label: formatSectionBadge(widget.sectionName),
            color: badgeColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.courseCode,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if ((widget.examTimeLabel ?? '').trim().isNotEmpty)
                  Text(
                    widget.examTimeLabel!.trim(),
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (roomLabel.isNotEmpty)
                  Text(
                    roomLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (consumedLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    consumedLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasPositiveScore(num value) => value > 0;

  String _formatScore(num value) {
    final asDouble = value.toDouble();
    if (asDouble <= 0) return '0';
    final rounded = asDouble.roundToDouble();
    if ((asDouble - rounded).abs() < 0.05) {
      return '${rounded.toInt()}';
    }
    return asDouble.toStringAsFixed(1);
  }

  String _compactMetricLine({
    required num teaching,
    required num fairness,
    required num behavior,
  }) {
    final parts = <String>[];
    if (_hasPositiveScore(teaching)) {
      parts.add('Teaching ${_formatScore(teaching)}/5');
    }
    if (_hasPositiveScore(fairness)) {
      parts.add('Fairness ${_formatScore(fairness)}/5');
    }
    if (_hasPositiveScore(behavior)) {
      parts.add('Behavior ${_formatScore(behavior)}/5');
    }
    return parts.join(' • ');
  }

  Widget _buildReviewSectionHeader({
    required BuildContext context,
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (secondaryActionLabel != null && onSecondaryAction != null)
          TextButton(
            onPressed: onSecondaryAction,
            child: Text(
              secondaryActionLabel,
              style: const TextStyle(color: BracuPalette.danger),
            ),
          ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  TextStyle _reviewBodyStyle(BuildContext context) {
    return TextStyle(
      color: BracuPalette.textPrimary(context),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle _reviewMetaStyle(BuildContext context) {
    return TextStyle(
      color: BracuPalette.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
  }

  Widget _buildQuoteReviewCard({
    required String comment,
    required String metricLine,
    required bool isApproved,
    VoidCallback? onDelete,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: 18,
            color: BracuPalette.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.trim(),
                  style: _reviewBodyStyle(context).copyWith(color: textPrimary),
                ),
                if (metricLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(metricLine, style: _reviewMetaStyle(context)),
                ],
                if (!isApproved) ...[
                  const SizedBox(height: 2),
                  Text('Pending approval', style: _reviewMetaStyle(context)),
                ],
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommunityReviewCard(FacultyReviewItem review) {
    final metricLine = _compactMetricLine(
      teaching: review.teaching,
      fairness: review.fairness,
      behavior: review.behavior,
    );
    return _buildQuoteReviewCard(
      comment: review.comment,
      metricLine: metricLine,
      isApproved: review.isApproved,
      onDelete:
          _busyWriteAction || review.canDelete != true || review.reviewId <= 0
          ? null
          : () => _deleteReview(review.reviewId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final sheetScroll = bracuBottomSheetScrollController(context);
    final materialSeenKeys = <String>{};
    String normalizeComment(String input) {
      return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    }

    final allReviewsRaw = _reviewFeed?.reviews ?? const <FacultyReviewItem>[];
    final reviewSeenKeys = <String>{};
    final allReviews = allReviewsRaw.where((review) {
      final key = review.reviewId > 0
          ? 'id:${review.reviewId}'
          : '${review.facultyInitial}|${review.overall}|${review.teaching}|${review.fairness}|${review.behavior}|${normalizeComment(review.comment)}';
      return reviewSeenKeys.add(key);
    }).toList();
    final nonEmptyReviews = allReviews
        .where((review) => review.comment.trim().isNotEmpty)
        .toList();
    FacultyReviewItem? myOwnedReview;
    for (final review in allReviews) {
      if (review.reviewId > 0 && review.canDelete == true) {
        myOwnedReview = review;
        break;
      }
    }
    final orderedReviews = <FacultyReviewItem>[
      if (myOwnedReview != null && myOwnedReview.comment.trim().isNotEmpty)
        myOwnedReview,
      ...nonEmptyReviews.where(
        (review) =>
            myOwnedReview == null || review.reviewId != myOwnedReview.reviewId,
      ),
    ];
    final displayReviews = _showAllReviews
        ? orderedReviews
        : orderedReviews.take(4).toList();
    final allMaterials = _materials.where((item) {
      final key = '${item.semester}|${item.courseCode}|${item.fileName}';
      return materialSeenKeys.add(key);
    }).toList();
    final displayMaterials = _showAllMaterials
        ? allMaterials
        : allMaterials.take(3).toList();
    final totalReviews = _reviewFeed?.faculty.stats.reviewsTotal ?? 0;
    final stats = _reviewFeed?.faculty.stats;
    final metricLine = _compactMetricLine(
      teaching: stats?.teaching ?? 0,
      fairness: stats?.fairness ?? 0,
      behavior: stats?.behavior ?? 0,
    );
    final hasSummaryScores =
        (stats?.overall ?? 0) > 0 ||
        (stats?.teaching ?? 0) > 0 ||
        (stats?.fairness ?? 0) > 0 ||
        (stats?.behavior ?? 0) > 0;
    final facultySummaryText = (_reviewFeed?.faculty.reviewSummary ?? '')
        .trim();
    final voteScore = _reviewFeed?.faculty.voteScore ?? 0;
    final upvotes = _reviewFeed?.faculty.upvotes ?? 0;
    final downvotes = _reviewFeed?.faculty.downvotes ?? 0;
    final hasVoteData = voteScore != 0 || upvotes > 0 || downvotes > 0;
    final hasSummaryCardContent =
        hasSummaryScores || facultySummaryText.isNotEmpty;
    final hasFacultyMeta =
        hasSummaryCardContent || facultySummaryText.isNotEmpty;
    final hasReviewHeader = _facultyInitial.isNotEmpty;
    final facultyFullName = (_reviewFeed?.faculty.name ?? '').trim();
    final reviewHeaderTitle = facultyFullName.isNotEmpty
        ? facultyFullName
        : (_facultyInitial.isNotEmpty
              ? 'Reviews for $_facultyInitial'
              : 'Faculty Reviews');
    final hasReviews = totalReviews > 0 || orderedReviews.isNotEmpty;
    final hasMyReview = myOwnedReview != null;
    final isAnyLoading =
        _reviewsLoading || _materialsLoading || _busyWriteAction;
    return ListView(
      controller: sheetScroll,
      children: [
        _buildSummaryCard(),
        if (isAnyLoading) ...[
          const SizedBox(height: 8),
          _buildCompactLoading(),
        ],
        if (hasReviewHeader) ...[
          const SizedBox(height: 8),
          _buildReviewSectionHeader(
            context: context,
            title: reviewHeaderTitle,
            actionLabel: widget.showActions
                ? (hasMyReview ? 'Edit' : 'Write')
                : null,
            onAction: widget.showActions && !_busyWriteAction
                ? _writeReview
                : null,
          ),
        ],
        if (!_reviewsLoading && _reviewsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              'Reviews not available right now.',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else if (!_reviewsLoading) ...[
          if (hasReviews || hasFacultyMeta) ...[
            if (hasSummaryCardContent)
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (metricLine.isNotEmpty) ...[
                      Text(metricLine, style: _reviewMetaStyle(context)),
                    ],
                    if (hasVoteData) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Votes $voteScore • Upvote $upvotes • Downvote $downvotes',
                        style: _reviewMetaStyle(context),
                      ),
                    ],
                    if (facultySummaryText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        facultySummaryText,
                        style: _reviewBodyStyle(
                          context,
                        ).copyWith(color: textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            if (hasSummaryCardContent) const SizedBox(height: 4),
            if (orderedReviews.isNotEmpty) ...[
              ...displayReviews.map((review) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildCommunityReviewCard(review),
                );
              }),
              if (orderedReviews.length > 4)
                buildCenteredOutlinedActionButton(
                  label: _showAllReviews ? 'Show Less' : 'Show More',
                  onPressed: () {
                    setState(() {
                      _showAllReviews = !_showAllReviews;
                    });
                  },
                  padding: const EdgeInsets.only(top: 0, bottom: 4),
                ),
            ],
          ] else if (hasReviewHeader) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Text(
                'No reviews yet. Be the first to write one!',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: BracuSectionTitle(title: 'Course Materials')),
            if (widget.showActions)
              TextButton(
                onPressed: _busyWriteAction ? null : _openAddMaterialSheet,
                child: const Text('Add'),
              ),
          ],
        ),
        if (!_materialsLoading && _materialsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              'Course materials not available right now.',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else if (!_materialsLoading && allMaterials.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              'No materials uploaded yet. Be the first to share one!',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else if (allMaterials.isNotEmpty) ...[
          ...displayMaterials.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final displayTitle = item.title.trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BracuCard(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _openMaterial(item),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${index + 1}. $displayTitle',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _materialSubtitle(item),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (item.canDelete == true)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete',
                        onPressed: _busyWriteAction
                            ? null
                            : () => _deleteMaterial(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (allMaterials.length > 3)
            buildCenteredOutlinedActionButton(
              label: _showAllMaterials ? 'Show Less' : 'Show More',
              onPressed: () {
                setState(() {
                  _showAllMaterials = !_showAllMaterials;
                });
              },
              padding: const EdgeInsets.only(top: 2, bottom: 8),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  String _materialSubtitle(CourseMaterialItem item) {
    final parsed = _parseMaterialMeta(item);
    final parts = <String>[];
    final uploader = parsed.uploaderName;
    if (uploader.isNotEmpty) {
      parts.add('by $uploader');
    } else {
      parts.add('by Unknown');
    }
    final semester = item.semester.trim();
    if (semester.isNotEmpty) {
      parts.add(semester);
    }
    final size = parsed.linkUrl.isNotEmpty
        ? ''
        : _formatFileSize(item.fileSize);
    if (size.isNotEmpty) {
      parts.add(size);
    }
    if (parsed.linkUrl.isNotEmpty) {
      parts.add(_materialLinkLabel(parsed.linkUrl));
    }
    return parts.isEmpty ? 'Course material' : parts.join(' • ');
  }

  String _materialLinkLabel(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final host = (uri?.host.trim() ?? '').toLowerCase();
    if (host.isEmpty) return 'Web';
    final cleanHost = host.startsWith('www.') ? host.substring(4) : host;
    final knownSource = _knownMaterialSource(cleanHost);
    if (knownSource != null) return knownSource;

    final parts = cleanHost
        .split('.')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Web';

    final source = parts.length >= 2 ? parts[parts.length - 2] : parts.first;
    return switch (source) {
      'fb' || 'facebook' => 'Facebook',
      'instagram' => 'Instagram',
      'youtube' || 'youtu' => 'YouTube',
      'google' => 'Google',
      'drive' => 'Google Drive',
      'github' => 'GitHub',
      'gitlab' => 'GitLab',
      'bitbucket' => 'Bitbucket',
      'linkedin' => 'LinkedIn',
      'preconnect' => 'PreConnect',
      _ => _titleCaseSource(source),
    };
  }

  String? _knownMaterialSource(String host) {
    if (host == 'drive.google.com') return 'Google Drive';
    if (host == 'docs.google.com') return 'Google Docs';
    if (host == 'forms.gle') return 'Google Forms';
    if (host == 'classroom.google.com') return 'Google Classroom';
    if (host == 'maps.google.com' || host == 'goo.gl') return 'Google';
    if (host == 'youtu.be' || host.endsWith('.youtube.com')) return 'YouTube';
    if (host == 'fb.watch' || host == 'm.me') return 'Facebook';
    if (host == 'x.com' || host == 'twitter.com') return 'X';
    if (host.endsWith('.sharepoint.com')) return 'SharePoint';
    if (host.endsWith('.notion.site') || host == 'notion.so') return 'Notion';
    if (host.endsWith('.canva.com') || host == 'canva.com') return 'Canva';
    if (host.endsWith('.dropbox.com') || host == 'dropbox.com') {
      return 'Dropbox';
    }
    if (host.endsWith('.box.com') || host == 'box.com') return 'Box';
    if (host == 'onedrive.live.com' || host == '1drv.ms') return 'OneDrive';
    if (host == 'mega.nz') return 'MEGA';
    if (host == 'mediafire.com' || host.endsWith('.mediafire.com')) {
      return 'MediaFire';
    }
    if (host == 't.me' || host == 'telegram.me') return 'Telegram';
    if (host == 'wa.me' || host == 'whatsapp.com') return 'WhatsApp';
    if (host == 'discord.gg' || host == 'discord.com') return 'Discord';
    if (host == 'stackoverflow.com') return 'Stack Overflow';
    if (host == 'medium.com') return 'Medium';
    if (host == 'reddit.com' || host.endsWith('.reddit.com')) return 'Reddit';
    if (host == 'bracu.ac.bd') return 'BRACU';
    if (host == 'bu.ac.bd') return 'BRACU';
    if (host == 'piazza.com') return 'Piazza';
    if (host == 'overleaf.com') return 'Overleaf';
    if (host == 'geeksforgeeks.org') return 'GeeksforGeeks';
    if (host == 'w3schools.com') return 'W3Schools';
    if (host == 'kaggle.com') return 'Kaggle';
    if (host == 'coursera.org') return 'Coursera';
    if (host == 'edx.org') return 'edX';
    if (host == 'khanacademy.org') return 'Khan Academy';
    if (host == 'archive.org') return 'Internet Archive';
    if (host == 'researchgate.net') return 'ResearchGate';
    if (host == 'academia.edu') return 'Academia';
    if (host == 'springer.com' || host.endsWith('.springer.com')) {
      return 'Springer';
    }
    if (host == 'ieee.org' || host.endsWith('.ieee.org')) return 'IEEE';
    if (host == 'acm.org' || host.endsWith('.acm.org')) return 'ACM';
    return null;
  }

  String _titleCaseSource(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-z0-9]+', caseSensitive: false), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Web';
    return cleaned
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        })
        .join(' ');
  }

  _MaterialMeta _parseMaterialMeta(CourseMaterialItem item) {
    var uploader = item.uploaderName.trim();
    var linkUrl = item.externalUrl.trim();
    final marker = _extractMetaMarker(item.description);
    if (marker != null) {
      final maybeUploader = (marker['uploader'] ?? '').trim();
      final maybeUrl = (marker['linkUrl'] ?? '').trim();
      if (uploader.isEmpty && maybeUploader.isNotEmpty) {
        uploader = maybeUploader;
      }
      if (linkUrl.isEmpty && maybeUrl.isNotEmpty) {
        linkUrl = maybeUrl;
      }
    }
    if (linkUrl.isEmpty &&
        item.contentType.trim().toLowerCase() == 'text/uri-list') {
      final extracted = _extractFirstHttpUrl(item.description);
      if (extracted.isNotEmpty) linkUrl = extracted;
    }
    return _MaterialMeta(uploaderName: uploader, linkUrl: linkUrl);
  }

  Map<String, String>? _extractMetaMarker(String description) {
    final raw = description.trim();
    if (raw.isEmpty) return null;
    final markerPrefix = 'PCMETA:';
    final markerLine = raw
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.startsWith(markerPrefix), orElse: () => '');
    if (markerLine.isEmpty) return null;
    final payload = markerLine.substring(markerPrefix.length).trim();
    if (payload.isEmpty) return null;
    try {
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map<String, dynamic>) {
        return map.map((key, value) => MapEntry(key, '${value ?? ''}'.trim()));
      }
      if (map is Map) {
        return map.cast<String, dynamic>().map(
          (key, value) => MapEntry(key, '${value ?? ''}'.trim()),
        );
      }
    } catch (_) {}
    return null;
  }

  String _extractFirstHttpUrl(String raw) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(raw);
    if (match == null) return '';
    return match.group(0)?.trim() ?? '';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _MaterialMeta {
  const _MaterialMeta({required this.uploaderName, required this.linkUrl});

  final String uploaderName;
  final String linkUrl;
}

enum _AddMaterialTab { file, link }

class _AddTabButton extends StatelessWidget {
  const _AddTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = BracuPalette.primary;
    final textColor = selected
        ? Colors.white
        : BracuPalette.textSecondary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:preconnect/api/advising_service.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/tools/advising_background.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/time_utils.dart';

typedef WishlistCreditLimit = ({int min, int max});

List<Map<String, dynamic>> parseWishlistCourseList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Invalid Wishlist course response.');
  }
  return decoded
      .map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid Wishlist course record.');
        }
        final course = item.cast<String, dynamic>();
        if (course['courseId'] is! num ||
            '${course['courseCode'] ?? ''}'.trim().isEmpty ||
            '${course['name'] ?? ''}'.trim().isEmpty ||
            course['courseCredit'] is! num) {
          throw const FormatException('Incomplete Wishlist course record.');
        }
        return course;
      })
      .toList(growable: false);
}

WishlistCreditLimit? parseWishlistCreditLimit(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return null;
  final min = decoded['minLoad'];
  final max = decoded['maxLoad'];
  if (min is! num || max is! num) return null;
  return (min: min.toInt(), max: max.toInt());
}

bool parseWishlistConfirmed(String body) {
  final decoded = jsonDecode(body);
  return decoded is Map && decoded['status'] == true;
}

String normalizeWishlistCode(String code) =>
    code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

String wishlistCourseCode(Map<String, dynamic> course) =>
    normalizeWishlistCode('${course['courseCode'] ?? ''}');

int wishlistCourseId(Map<String, dynamic> course) =>
    (course['courseId'] as num).toInt();

int wishlistCourseCredit(Map<String, dynamic> course) =>
    (course['courseCredit'] as num).toInt();

int wishlistCredits(Iterable<Map<String, dynamic>> courses) =>
    courses.fold(0, (sum, course) => sum + wishlistCourseCredit(course));

bool isWithinWishlistLimit(int credits, WishlistCreditLimit? limit) =>
    limit == null || (credits >= limit.min && credits <= limit.max);

bool wishlistContainsCourse(
  Iterable<Map<String, dynamic>> courses,
  Map<String, dynamic> course,
) {
  final courseId = wishlistCourseId(course);
  return courses.any((item) => wishlistCourseId(item) == courseId);
}

List<Map<String, dynamic>> mergeWishlistCourseOptions(
  Iterable<Map<String, dynamic>> selectedCourses,
  Iterable<Map<String, dynamic>> offeredCourses,
) {
  final coursesById = <int, Map<String, dynamic>>{};
  for (final course in selectedCourses) {
    coursesById[wishlistCourseId(course)] = course;
  }
  for (final course in offeredCourses) {
    coursesById.putIfAbsent(wishlistCourseId(course), () => course);
  }
  return coursesById.values.toList(growable: false);
}

Map<String, dynamic>? findWishlistCourse(
  Iterable<Map<String, dynamic>> courses,
  String code,
) {
  final normalized = normalizeWishlistCode(code);
  for (final course in courses) {
    if (wishlistCourseCode(course) == normalized) return course;
  }
  return null;
}

String wishlistCourseCount(int count) => countLabel(count, 'course');

enum WishlistQueueStatus { queued, adding, failed }

class WishlistQueueItem {
  WishlistQueueItem({
    required String code,
    required this.name,
    required this.credit,
    this.status = WishlistQueueStatus.queued,
    this.note,
  }) : code = normalizeWishlistCode(code);

  final String code;
  final String name;
  final int credit;
  WishlistQueueStatus status;
  String? note;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'name': name,
    'credit': credit,
    'status': status.name,
    if (note != null) 'note': note,
  };

  factory WishlistQueueItem.fromJson(Map<String, dynamic> json) {
    final credit = json['credit'];
    return WishlistQueueItem(
      code: '${json['code'] ?? ''}',
      name: '${json['name'] ?? ''}',
      credit: credit is num ? credit.toInt() : 0,
      status:
          WishlistQueueStatus.values.asNameMap()[json['status']] ??
          WishlistQueueStatus.queued,
      note: json['note'] is String ? json['note'] as String : null,
    );
  }
}

class WishlistService {
  WishlistService({ApiClient? client}) : _client = client ?? ApiClient();

  static const Set<int> _mutationStatusCodes = <int>{200, 201, 204};

  final ApiClient _client;
  final AdvisingHelperService _advising = AdvisingHelperService();

  String _url(String path) => '${ApiConfig.connectApiBase}$path';

  Map<String, String> _headers(String publicKey) =>
      _advising.buildRequestHeaders(publicKey: publicKey);

  Future<WishlistCreditLimit?> openSession(
    String portfolioId,
    String publicKey,
  ) async {
    final response = await _client.authenticatedRequest(
      'POST',
      _url(ApiConfig.wishlistSessionPath(portfolioId, publicKey)),
      additionalHeaders: _advising.buildRequestHeaders(
        contentType: 'text/plain',
      ),
    );
    return parseWishlistCreditLimit(response.body);
  }

  Future<List<Map<String, dynamic>>> fetchWishlist(
    String portfolioId,
    String publicKey,
  ) async {
    final response = await _client.authenticatedGet(
      _url(ApiConfig.wishlistCoursesPath(portfolioId)),
      additionalHeaders: _headers(publicKey),
      bypassCache: true,
    );
    return parseWishlistCourseList(response.body);
  }

  Future<List<Map<String, dynamic>>> fetchOffered(
    String portfolioId,
    String publicKey,
  ) async {
    final response = await _client.authenticatedGet(
      _url(ApiConfig.wishlistOfferedCoursesPath(portfolioId)),
      additionalHeaders: _headers(publicKey),
      bypassCache: true,
    );
    return parseWishlistCourseList(response.body);
  }

  Future<bool> fetchConfirmed(String portfolioId, String publicKey) async {
    final response = await _client.authenticatedGet(
      _url(ApiConfig.wishlistStatusPath(portfolioId)),
      additionalHeaders: _headers(publicKey),
      bypassCache: true,
    );
    return parseWishlistConfirmed(response.body);
  }

  Future<void> addCourse(
    String portfolioId,
    String publicKey,
    Map<String, dynamic> course,
  ) async {
    await _client.authenticatedRequest(
      'POST',
      _url(ApiConfig.wishlistMutationPath),
      body: jsonEncode({
        'courseId': wishlistCourseId(course),
        'courseCredit': wishlistCourseCredit(course),
        'studentPortfolioId': int.parse(portfolioId),
      }),
      additionalHeaders: _headers(publicKey),
      acceptedStatusCodes: _mutationStatusCodes,
    );
  }

  Future<void> removeCourse(
    String portfolioId,
    String publicKey,
    Map<String, dynamic> course,
  ) async {
    await _client.authenticatedRequest(
      'DELETE',
      _url(ApiConfig.wishlistMutationPath),
      body: jsonEncode({
        'courseId': wishlistCourseId(course),
        'studentPortfolioId': int.parse(portfolioId),
      }),
      additionalHeaders: _headers(publicKey),
      acceptedStatusCodes: _mutationStatusCodes,
    );
  }

  Future<void> confirm(String portfolioId, String publicKey) async {
    await _client.authenticatedRequest(
      'PUT',
      _url(ApiConfig.wishlistConfirmPath(portfolioId)),
      body: '{}',
      additionalHeaders: _headers(publicKey),
      acceptedStatusCodes: _mutationStatusCodes,
    );
  }
}

class WishlistAutoEngine extends ChangeNotifier with ActivityLogger {
  WishlistAutoEngine._internal();
  static final WishlistAutoEngine instance = WishlistAutoEngine._internal();
  factory WishlistAutoEngine() => instance;

  static const Duration _tickInterval = Duration(seconds: 1);
  static const Duration _openLead = Duration(seconds: 5);
  static const Duration _retryLogInterval = Duration(seconds: 30);

  final WishlistService _service = WishlistService();
  final List<WishlistQueueItem> queue = <WishlistQueueItem>[];

  bool isRunning = false;
  DateTime? opensAt;
  VoidCallback? onWishlistChanged;
  bool _isLoaded = false;
  bool _isTicking = false;
  bool _isSessionOpen = false;
  bool _hasLoggedWaiting = false;
  int _generation = 0;
  Timer? _timer;
  String? _portfolioId;
  String? _publicKey;
  WishlistCreditLimit? _creditLimit;
  DateTime? _lastRetryLog;

  Future<void> load() async {
    if (_isLoaded) return;
    _isLoaded = true;
    try {
      final raw = await AppStorage.instance.getString(
        StorageKeys.wishlistQueue,
      );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      queue
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map(
            (item) => WishlistQueueItem.fromJson(item.cast<String, dynamic>()),
          ),
        );
      for (final item in queue) {
        if (item.status == WishlistQueueStatus.adding) {
          item.status = WishlistQueueStatus.queued;
        }
      }
      notifyListeners();
    } on FormatException {
      queue.clear();
    }
  }

  WishlistQueueItem? queuedItem(String code) {
    final normalized = normalizeWishlistCode(code);
    for (final item in queue) {
      if (item.code == normalized) return item;
    }
    return null;
  }

  bool isQueued(String code) => queuedItem(code) != null;

  void toggle(String code, String name, int credit) {
    final existing = queuedItem(code);
    if (existing != null) {
      if (existing.status == WishlistQueueStatus.adding) return;
      queue.remove(existing);
      addLog('Removed ${existing.code} from the queue');
    } else {
      final item = WishlistQueueItem(code: code, name: name, credit: credit);
      queue.add(item);
      addLog('Queued ${item.code}');
    }
    _saveQueue();
    notifyListeners();
  }

  void start({
    required String portfolioId,
    DateTime? opensAt,
    VoidCallback? onWishlistChanged,
  }) {
    if (isRunning) return;
    _generation++;
    _portfolioId = portfolioId;
    this.opensAt = opensAt;
    this.onWishlistChanged = onWishlistChanged;
    _isSessionOpen = false;
    _hasLoggedWaiting = false;
    _lastRetryLog = null;
    for (final item in queue) {
      item
        ..status = WishlistQueueStatus.queued
        ..note = null;
    }
    isRunning = true;
    addLog('Wishlist Helper started');
    unawaited(
      AdvisingBackground.start(
        title: 'Wishlist Helper Active',
        message: 'Adding ${wishlistCourseCount(queue.length)} to the Wishlist',
      ),
    );
    unawaited(AdvisingBackground.setKeepAwake(true));
    unawaited(AdvisingBackground.requestBatteryOptimizationExemptionIfNeeded());
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void stop({String? message}) {
    if (!isRunning) return;
    _generation++;
    isRunning = false;
    _timer?.cancel();
    _timer = null;
    _isSessionOpen = false;
    for (final item in queue) {
      if (item.status == WishlistQueueStatus.adding) {
        item.status = WishlistQueueStatus.queued;
      }
    }
    unawaited(AdvisingBackground.stop());
    unawaited(AdvisingBackground.setKeepAwake(false));
    _saveQueue();
    addLog(message ?? 'Wishlist Helper stopped');
  }

  Future<void> _tick() async {
    final portfolioId = _portfolioId;
    if (!isRunning || _isTicking || portfolioId == null) return;
    _isTicking = true;
    final generation = _generation;
    try {
      if (!_isSessionOpen) {
        if (_isBeforeOpening()) return;
        if (!await _openSession(portfolioId, generation)) return;
      }
      await _processQueue(portfolioId, generation);
    } on ApiException catch (error) {
      if (generation != _generation) return;
      if (error.statusCode >= 400 && error.statusCode < 500) {
        _isSessionOpen = false;
      }
      _logRetry(advisingErrorMessage(error));
    } catch (error) {
      if (generation != _generation) return;
      _logRetry(advisingErrorMessage(error));
    } finally {
      _isTicking = false;
    }
  }

  bool _isBeforeOpening() {
    final opensAt = this.opensAt;
    if (opensAt == null) return false;
    if (!DateTime.now().isBefore(opensAt.subtract(_openLead))) return false;
    if (!_hasLoggedWaiting) {
      _hasLoggedWaiting = true;
      addLog(
        'Waiting for the wishlist to open at ${AppTime.formatDateTime(opensAt)}',
      );
    }
    return true;
  }

  Future<bool> _openSession(String portfolioId, int generation) async {
    final publicKey = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final limit = await _service.openSession(portfolioId, publicKey);
      if (generation != _generation) return false;
      _creditLimit = limit;
      _publicKey = publicKey;
      _isSessionOpen = true;
      addLog(
        limit == null
            ? 'Wishlist is open'
            : 'Wishlist is open (${limit.min}–${limit.max} credits)',
      );
      return true;
    } on ApiException catch (error) {
      if (generation != _generation) return false;
      if (error.statusCode == 404) {
        _logRetry('Wishlist is not open yet, retrying');
      } else if (error.statusCode == 412) {
        stop(message: 'Wishlist phase is already completed');
      } else {
        _logRetry(advisingErrorMessage(error));
      }
      return false;
    }
  }

  Future<void> _processQueue(String portfolioId, int generation) async {
    final publicKey = _publicKey;
    if (publicKey == null) return;
    final pending = queue
        .where((item) => item.status != WishlistQueueStatus.failed)
        .toList(growable: false);
    if (pending.isEmpty) {
      await _finish(portfolioId, publicKey, generation);
      return;
    }

    final results = await Future.wait([
      _service.fetchWishlist(portfolioId, publicKey),
      _service.fetchOffered(portfolioId, publicKey),
    ]);
    if (generation != _generation) return;
    final wishlist = results[0];
    final offered = results[1];
    var hasAdded = false;

    for (final item in pending) {
      if (generation != _generation) return;
      if (findWishlistCourse(wishlist, item.code) != null) {
        queue.remove(item);
        addLog('${item.code} is already in the wishlist');
        continue;
      }
      final course = findWishlistCourse(offered, item.code);
      if (course == null) {
        _markFailed(item, 'Not offered');
        continue;
      }
      if (await _addQueued(item, course, portfolioId, publicKey, generation)) {
        hasAdded = true;
      }
    }

    if (generation != _generation) return;
    _saveQueue();
    notifyListeners();
    if (hasAdded) onWishlistChanged?.call();
  }

  Future<bool> _addQueued(
    WishlistQueueItem item,
    Map<String, dynamic> course,
    String portfolioId,
    String publicKey,
    int generation,
  ) async {
    item.status = WishlistQueueStatus.adding;
    notifyListeners();
    try {
      await _service.addCourse(portfolioId, publicKey, course);
      if (generation != _generation) return false;
      queue.remove(item);
      addLog('Added ${item.code}');
      return true;
    } on ApiException catch (error) {
      if (generation != _generation) return false;
      if (error.statusCode >= 400 && error.statusCode < 500) {
        _markFailed(item, advisingErrorMessage(error));
      } else {
        item.status = WishlistQueueStatus.queued;
        _logRetry(advisingErrorMessage(error));
      }
      return false;
    } catch (error) {
      if (generation != _generation) return false;
      item.status = WishlistQueueStatus.queued;
      _logRetry(advisingErrorMessage(error));
      return false;
    }
  }

  void _markFailed(WishlistQueueItem item, String note) {
    item
      ..status = WishlistQueueStatus.failed
      ..note = note;
    addLog('Could not add ${item.code}: $note');
  }

  Future<void> _finish(
    String portfolioId,
    String publicKey,
    int generation,
  ) async {
    final wishlist = await _service.fetchWishlist(portfolioId, publicKey);
    final isConfirmed = await _service.fetchConfirmed(portfolioId, publicKey);
    if (generation != _generation) return;
    final count = wishlist.length;
    final credits = wishlistCredits(wishlist);
    final limit = _creditLimit;
    if (isConfirmed) {
      stop(message: 'Wishlist is already confirmed');
      return;
    }
    if (count == 0) {
      stop(message: 'Wishlist is empty; not confirmed');
      return;
    }
    if (limit != null && !isWithinWishlistLimit(credits, limit)) {
      stop(
        message:
            '$credits credits is outside ${limit.min}–${limit.max}; '
            'not confirmed',
      );
      return;
    }
    try {
      await _service.confirm(portfolioId, publicKey);
    } on ApiException catch (error) {
      if (generation != _generation) return;
      if (error.statusCode >= 400 && error.statusCode < 500) {
        stop(message: advisingErrorMessage(error));
        return;
      }
      rethrow;
    }
    if (generation != _generation) return;
    addLog('Confirmed the wishlist');
    onWishlistChanged?.call();
    stop(
      message:
          'Wishlist confirmed with ${wishlistCourseCount(count)} '
          '($credits credits)',
    );
  }

  void _logRetry(String message) {
    final now = DateTime.now();
    final last = _lastRetryLog;
    if (last != null && now.difference(last) < _retryLogInterval) return;
    _lastRetryLog = now;
    addLog(message);
  }

  void _saveQueue() {
    final encoded = jsonEncode(queue.map((item) => item.toJson()).toList());
    unawaited(
      AppStorage.instance.setString(StorageKeys.wishlistQueue, encoded),
    );
  }
}

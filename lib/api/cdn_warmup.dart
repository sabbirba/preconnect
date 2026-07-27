import 'dart:async';

class CdnWarmupService {
  CdnWarmupService._();

  static final CdnWarmupService instance = CdnWarmupService._();

  Future<void> warmPublicCdnData({bool forceRefresh = false}) async {}
}

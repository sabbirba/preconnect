import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppImageCache extends CacheManager with ImageCacheManager {
  AppImageCache._()
    : super(
        Config(
          'libCachedImageData',
          repo: kIsWeb
              ? NonStoringObjectProvider()
              : JsonCacheInfoRepository(databaseName: 'libCachedImageData'),
        ),
      );

  static final AppImageCache instance = AppImageCache._();
}

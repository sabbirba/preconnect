export 'platform_stub.dart'
    if (dart.library.html) 'package:preconnect/widgets/image_web.dart'
    if (dart.library.io) 'platform_flutter.dart'
    show WebSafeNetworkImage;

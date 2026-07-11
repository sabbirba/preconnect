import 'dart:convert';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

String _decode(String obfuscated) {
  return utf8.decode(base64.decode(obfuscated.split('').reversed.join()));
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static final FirebaseOptions web = FirebaseOptions(
    apiKey: _decode('F9lNFhnZjNjet0SMXdTN2kDRnNESrlTcCVFMKJlY5EmQ5NVY6lUQ'),
    appId: _decode('==QN1gjZ2gDOmlTM2ImNkFTOyM2YihzY6IWZ3pjNzETM0kDOwUzM1oTM'),
    messagingSenderId: '53508941136',
    projectId: 'preconnect-bracu',
    authDomain: 'preconnect-bracu.firebaseapp.com',
    storageBucket: 'preconnect-bracu.firebasestorage.app',
    measurementId: 'G-MJ066FW9N7',
  );

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: _decode('VdmU3dUaVh0NzUkbIdjZiljemVVMPlHbkRzTPNDZV1CR5NVY6lUQ'),
    appId: _decode(
      '=UTN4YmN4UWZwQWYxUWYwYjZyEzMyAjOkl2byRmbhpjNzETM0kDOwUzM1oTM',
    ),
    messagingSenderId: '53508941136',
    projectId: 'preconnect-bracu',
    storageBucket: 'preconnect-bracu.firebasestorage.app',
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: _decode('rp3brFXV3o1csJDeRB1Qt8GdFt2QuxUeMVVNxZ3QaVzQ5NVY6lUQ'),
    appId: _decode('==QN1gjZ2gzMxQTO1MWM5I2MlhDOmFGZ6M3bppjNzETM0kDOwUzM1oTM'),
    messagingSenderId: '53508941136',
    projectId: 'preconnect-bracu',
    storageBucket: 'preconnect-bracu.firebasestorage.app',
    iosBundleId: 'com.sabbirba.preconnect',
  );

  static final FirebaseOptions macos = FirebaseOptions(
    apiKey: _decode('rp3brFXV3o1csJDeRB1Qt8GdFt2QuxUeMVVNxZ3QaVzQ5NVY6lUQ'),
    appId: _decode('==QN1gjZ2gzMxQTO1MWM5I2MlhDOmFGZ6M3bppjNzETM0kDOwUzM1oTM'),
    messagingSenderId: '53508941136',
    projectId: 'preconnect-bracu',
    storageBucket: 'preconnect-bracu.firebasestorage.app',
    iosBundleId: 'com.sabbirba.preconnect',
  );
}

import 'dart:ffi' as ffi;
import 'dart:io';

typedef _NativeBackendName = ffi.Pointer<ffi.Uint8> Function();
typedef _NativeFreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>);
typedef _NativeFreeString = void Function(ffi.Pointer<ffi.Uint8>);

class NativeBridge {
  NativeBridge._();

  static final ffi.DynamicLibrary? _library = _openLibrary();
  static final _NativeBackendName? _backendName = _lookupBackendName();
  static final _NativeFreeString? _freeString = _lookupFreeString();

  static bool get isSupported => _library != null;

  static String? tryBackendName() {
    final backendName = _backendName;
    final freeString = _freeString;
    if (backendName == null || freeString == null) return null;

    final pointer = backendName();
    if (pointer == ffi.nullptr) return null;
    try {
      return _stringFromNativeUtf8(pointer);
    } finally {
      freeString(pointer);
    }
  }

  static ffi.DynamicLibrary? _openLibrary() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return ffi.DynamicLibrary.open('libpreconnect_native.so');
      }
      if (Platform.isIOS || Platform.isMacOS) {
        return ffi.DynamicLibrary.process();
      }
      if (Platform.isWindows) {
        return ffi.DynamicLibrary.open('preconnect_native.dll');
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static _NativeBackendName? _lookupBackendName() {
    try {
      return _library?.lookupFunction<_NativeBackendName, _NativeBackendName>(
        'preconnect_native_backend_name',
      );
    } catch (_) {
      return null;
    }
  }

  static _NativeFreeString? _lookupFreeString() {
    try {
      return _library
          ?.lookupFunction<_NativeFreeStringNative, _NativeFreeString>(
            'preconnect_native_free_string',
          );
    } catch (_) {
      return null;
    }
  }

  static String _stringFromNativeUtf8(ffi.Pointer<ffi.Uint8> pointer) {
    var length = 0;
    while (pointer[length] != 0) {
      length++;
    }
    return String.fromCharCodes(pointer.asTypedList(length));
  }
}

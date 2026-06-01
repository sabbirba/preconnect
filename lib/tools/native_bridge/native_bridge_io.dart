import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class NativeBridge {
  NativeBridge._();

  static final ffi.DynamicLibrary? _library = _openLibrary();
  static final _NativeBackendName? _backendName = _lookupBackendName();
  static final _NativeFreeString? _freeString = _lookupFreeString();
  static final _NativeValidateJson? _validateJson = _lookupValidateJson();
  static final _NativeEncrypt? _encrypt = _lookupEncrypt();
  static final _NativeDecrypt? _decrypt = _lookupDecrypt();
  static final _NativeFreeBytes? _freeBytes = _lookupFreeBytes();
  static final _NativeExpandAndMergeSchedules? _expandAndMergeSchedules =
      _lookupExpandAndMergeSchedules();

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

  static bool validateJson(String jsonStr) {
    final validate = _validateJson;
    if (validate == null) return false;

    final nativeString = jsonStr.toNativeUtf8();
    try {
      return validate(nativeString.cast<ffi.Char>()) == 1;
    } catch (_) {
      return false;
    } finally {
      malloc.free(nativeString);
    }
  }

  static Uint8List? encryptBytes(Uint8List key, Uint8List data) {
    final enc = _encrypt;
    final free = _freeBytes;
    if (enc == null || free == null || key.length != 32) return null;

    final nativeKey = malloc<ffi.Uint8>(32);
    final nativeData = malloc<ffi.Uint8>(data.length);
    final outLenPointer = malloc<ffi.Int32>();

    try {
      nativeKey.asTypedList(32).setAll(0, key);
      nativeData.asTypedList(data.length).setAll(0, data);

      final resultPtr = enc(nativeKey, nativeData, data.length, outLenPointer);
      if (resultPtr == ffi.nullptr) return null;

      final outLen = outLenPointer.value;
      try {
        final result = Uint8List.fromList(resultPtr.asTypedList(outLen));
        return result;
      } finally {
        free(resultPtr, outLen);
      }
    } catch (_) {
      return null;
    } finally {
      malloc.free(nativeKey);
      malloc.free(nativeData);
      malloc.free(outLenPointer);
    }
  }

  static Uint8List? decryptBytes(Uint8List key, Uint8List data) {
    final dec = _decrypt;
    final free = _freeBytes;
    if (dec == null || free == null || key.length != 32) return null;

    final nativeKey = malloc<ffi.Uint8>(32);
    final nativeData = malloc<ffi.Uint8>(data.length);
    final outLenPointer = malloc<ffi.Int32>();

    try {
      nativeKey.asTypedList(32).setAll(0, key);
      nativeData.asTypedList(data.length).setAll(0, data);

      final resultPtr = dec(nativeKey, nativeData, data.length, outLenPointer);
      if (resultPtr == ffi.nullptr) return null;

      final outLen = outLenPointer.value;
      try {
        final result = Uint8List.fromList(resultPtr.asTypedList(outLen));
        return result;
      } finally {
        free(resultPtr, outLen);
      }
    } catch (_) {
      return null;
    } finally {
      malloc.free(nativeKey);
      malloc.free(nativeData);
      malloc.free(outLenPointer);
    }
  }

  static String? expandAndMergeSchedules({
    required String sectionsJson,
    required String extraWindowsJson,
    required int semesterSessionId,
    required bool isRamadan,
    required int nowMs,
    required int timezoneOffsetMs,
  }) {
    final func = _expandAndMergeSchedules;
    final free = _freeString;
    if (func == null || free == null) return null;

    final nativeSections = sectionsJson.toNativeUtf8();
    final nativeExtra = extraWindowsJson.toNativeUtf8();
    try {
      final resultPtr = func(
        nativeSections.cast<ffi.Char>(),
        nativeExtra.cast<ffi.Char>(),
        semesterSessionId,
        isRamadan ? 1 : 0,
        nowMs,
        timezoneOffsetMs,
      );
      if (resultPtr == ffi.nullptr) return null;
      try {
        return _stringFromNativeUtf8(resultPtr);
      } finally {
        free(resultPtr);
      }
    } catch (_) {
      return null;
    } finally {
      malloc.free(nativeSections);
      malloc.free(nativeExtra);
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

  static _NativeValidateJson? _lookupValidateJson() {
    try {
      return _library
          ?.lookupFunction<_NativeValidateJsonNative, _NativeValidateJson>(
            'preconnect_native_validate_json',
          );
    } catch (_) {
      return null;
    }
  }

  static _NativeEncrypt? _lookupEncrypt() {
    try {
      return _library?.lookupFunction<_NativeEncryptNative, _NativeEncrypt>(
        'preconnect_native_encrypt',
      );
    } catch (_) {
      return null;
    }
  }

  static _NativeDecrypt? _lookupDecrypt() {
    try {
      return _library?.lookupFunction<_NativeDecryptNative, _NativeDecrypt>(
        'preconnect_native_decrypt',
      );
    } catch (_) {
      return null;
    }
  }

  static _NativeFreeBytes? _lookupFreeBytes() {
    try {
      return _library?.lookupFunction<_NativeFreeBytesNative, _NativeFreeBytes>(
        'preconnect_native_free_bytes',
      );
    } catch (_) {
      return null;
    }
  }

  static _NativeExpandAndMergeSchedules? _lookupExpandAndMergeSchedules() {
    try {
      return _library?.lookupFunction<
        _NativeExpandAndMergeSchedulesNative,
        _NativeExpandAndMergeSchedules
      >('preconnect_native_expand_and_merge_class_schedules');
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

typedef _NativeBackendName = ffi.Pointer<ffi.Uint8> Function();
typedef _NativeFreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>);
typedef _NativeFreeString = void Function(ffi.Pointer<ffi.Uint8>);
typedef _NativeValidateJsonNative = ffi.Int32 Function(ffi.Pointer<ffi.Char>);
typedef _NativeValidateJson = int Function(ffi.Pointer<ffi.Char>);

typedef _NativeEncryptNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> key,
      ffi.Pointer<ffi.Uint8> data,
      ffi.Int32 dataLen,
      ffi.Pointer<ffi.Int32> outLen,
    );
typedef _NativeEncrypt =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> key,
      ffi.Pointer<ffi.Uint8> data,
      int dataLen,
      ffi.Pointer<ffi.Int32> outLen,
    );

typedef _NativeDecryptNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> key,
      ffi.Pointer<ffi.Uint8> data,
      ffi.Int32 dataLen,
      ffi.Pointer<ffi.Int32> outLen,
    );
typedef _NativeDecrypt =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Uint8> key,
      ffi.Pointer<ffi.Uint8> data,
      int dataLen,
      ffi.Pointer<ffi.Int32> outLen,
    );

typedef _NativeFreeBytesNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr, ffi.Int32 len);
typedef _NativeFreeBytes = void Function(ffi.Pointer<ffi.Uint8> ptr, int len);

typedef _NativeExpandAndMergeSchedulesNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Char> sectionsJson,
      ffi.Pointer<ffi.Char> extraWindowsJson,
      ffi.Int32 semesterSessionId,
      ffi.Int32 isRamadan,
      ffi.Int64 nowMs,
      ffi.Int64 timezoneOffsetMs,
    );
typedef _NativeExpandAndMergeSchedules =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Char> sectionsJson,
      ffi.Pointer<ffi.Char> extraWindowsJson,
      int semesterSessionId,
      int isRamadan,
      int nowMs,
      int timezoneOffsetMs,
    );

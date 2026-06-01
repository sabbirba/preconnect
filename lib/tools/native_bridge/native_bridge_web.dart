import 'dart:typed_data';

class NativeBridge {
  NativeBridge._();

  static bool get isSupported => false;

  static String? tryBackendName() => null;

  static Uint8List? encryptBytes(Uint8List key, Uint8List data) => null;
  static Uint8List? decryptBytes(Uint8List key, Uint8List data) => null;

  static String? expandAndMergeSchedules({
    required String sectionsJson,
    required String extraWindowsJson,
    required int semesterSessionId,
    required bool isRamadan,
    required int nowMs,
    required int timezoneOffsetMs,
  }) => null;
}

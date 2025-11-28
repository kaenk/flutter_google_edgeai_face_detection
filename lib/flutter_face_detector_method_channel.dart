import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_face_detector_platform_interface.dart';

/// An implementation of [FlutterFaceDetectorPlatform] that uses method channels.
class MethodChannelFlutterFaceDetector extends FlutterFaceDetectorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_face_detector');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<Map<String, dynamic>> faceDetectionFromImage(
      Uint8List imageData) async {
    final result = await methodChannel.invokeMethod<dynamic>(
      'faceDetectionFromImage',
      <dynamic, dynamic>{'image': imageData}, // 👈 明確用 dynamic key/value
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    } else {
      return {'error': 'Invalid response from native'};
    }
  }

  @override
  Future<Map<String, dynamic>> faceLandmarkDetectionFromImage(
      Uint8List imageData) async {
    final result = await methodChannel.invokeMethod<dynamic>(
      'faceLandmarkDetectionFromImage',
      <dynamic, dynamic>{'image': imageData},
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    } else {
      return {'error': 'Invalid response from native'};
    }
  }
}

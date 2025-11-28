import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_face_detector_method_channel.dart';

abstract class FlutterFaceDetectorPlatform extends PlatformInterface {
  /// Constructs a FlutterFaceDetectorPlatform.
  FlutterFaceDetectorPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFaceDetectorPlatform _instance =
      MethodChannelFlutterFaceDetector();

  /// The default instance of [FlutterFaceDetectorPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterFaceDetector].
  static FlutterFaceDetectorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFaceDetectorPlatform] when
  /// they register themselves.
  static set instance(FlutterFaceDetectorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<Map<String, dynamic>> faceDetectionFromImage(Uint8List imageData) {
    throw UnimplementedError(
        'faceDetectionFromImage(Uint8List imageData) has not been implemented.');
  }

  Future<Map<String, dynamic>> faceLandmarkDetectionFromImage(
      Uint8List imageData) {
    throw UnimplementedError(
        'faceLandmarkDetectionFromImage(Uint8List imageData) has not been implemented.');
  }
}

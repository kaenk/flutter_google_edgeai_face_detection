import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_face_detector/flutter_face_detector.dart';
import 'package:flutter_face_detector/flutter_face_detector_platform_interface.dart';
import 'package:flutter_face_detector/flutter_face_detector_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterFaceDetectorPlatform
    with MockPlatformInterfaceMixin
    implements FlutterFaceDetectorPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<double> faceDetectionFromImage(Uint8List imageData) => Future.value(1);
}

void main() {
  final FlutterFaceDetectorPlatform initialPlatform =
      FlutterFaceDetectorPlatform.instance;

  test('$MethodChannelFlutterFaceDetector is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterFaceDetector>());
  });

  test('getPlatformVersion', () async {
    FlutterFaceDetector flutterFaceDetectorPlugin = FlutterFaceDetector();
    MockFlutterFaceDetectorPlatform fakePlatform =
        MockFlutterFaceDetectorPlatform();
    FlutterFaceDetectorPlatform.instance = fakePlatform;

    expect(await flutterFaceDetectorPlugin.getPlatformVersion(), '42');
  });
}

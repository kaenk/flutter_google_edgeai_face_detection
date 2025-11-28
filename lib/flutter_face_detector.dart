import 'dart:typed_data';

import 'flutter_face_detector_platform_interface.dart';

class FlutterFaceDetector {
  Future<String?> getPlatformVersion() {
    return FlutterFaceDetectorPlatform.instance.getPlatformVersion();
  }

  Future<Map<String, dynamic>> faceDetectionFromImage(Uint8List imageData) {
    return FlutterFaceDetectorPlatform.instance
        .faceDetectionFromImage(imageData);
  }

  /// 执行人脸关键点检测
  /// 返回包含关键点坐标、置信度和推理时间的 Map
  /// landmarks: List<List<double>> - 每个检测到的人脸的关键点列表，每个关键点是 [x, y, z] 坐标
  /// confidence: String - 检测置信度（百分比）
  /// inferenceTime: String - 推理时间（毫秒）
  Future<Map<String, dynamic>> faceLandmarkDetectionFromImage(
      Uint8List imageData) {
    return FlutterFaceDetectorPlatform.instance
        .faceLandmarkDetectionFromImage(imageData);
  }
}

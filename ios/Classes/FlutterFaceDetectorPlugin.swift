import Flutter
import UIKit
import MediaPipeTasksVision
//import os

public class FlutterFaceDetectorPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_face_detector", binaryMessenger: registrar.messenger())
    let instance = FlutterFaceDetectorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result(InferenceConfigurationManager.sharedInstance.modelPath ?? "")

    case "faceDetectionFromImage":
      // 取得 imageData
      guard let args = call.arguments as? [String: Any],
        let imageData = args["image"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "NO_IMAGE", message: "No image data found", details: nil))
        return
      }

      guard let uiImage = UIImage(data: imageData.data) else {
        result(FlutterError(code: "INVALID_IMAGE", message: "Unable to decode image", details: nil))
        return
      }

      // 初始化偵測服務
      guard
        let service = FaceDetectorService.stillImageDetectorService(
          modelPath: InferenceConfigurationManager.sharedInstance.modelPath,
          minDetectionConfidence: InferenceConfigurationManager.sharedInstance
            .minDetectionConfidence,
          minSuppressionThreshold: InferenceConfigurationManager.sharedInstance
            .minSuppressionThreshold,
          delegate: InferenceConfigurationManager.sharedInstance.delegate
        )
      else {
        result(
          FlutterError(
            code: "INIT_FAILED", message: "Failed to initialize FaceDetectorService", details: nil))
        return
      }

      // 執行臉部偵測
      guard let resultBundle = service.detect(image: uiImage) else {
        result(
          FlutterError(code: "DETECTION_FAILED", message: "No face detection result", details: nil))
        return
      }

      // ✅ 取得最高信心值
      var maxConfidence: Float = 0.0
      if let firstResult = resultBundle.faceDetectorResults.first, 
        let result = firstResult {
        let detections = result.detections
        for detection in detections {
          if let score = detection.categories.first?.score, score > maxConfidence {
            maxConfidence = score
          }
        }
      }
            
      // ✅ 格式化輸出
      let inferenceTimeString = String(format: "%.2fms", resultBundle.inferenceTime)
      let confidenceString = String(format: "%.2f", maxConfidence * 100) + "%"  // 轉成百分比

      // ✅ 同時回傳兩個資訊
      result([
        "inferenceTime": inferenceTimeString,
        "confidence": confidenceString,
      ])

    case "faceLandmarkDetectionFromImage":
      // 取得 imageData
      guard let args = call.arguments as? [String: Any],
        let imageData = args["image"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "NO_IMAGE", message: "No image data found", details: nil))
        return
      }

      guard let uiImage = UIImage(data: imageData.data) else {
        result(FlutterError(code: "INVALID_IMAGE", message: "Unable to decode image", details: nil))
        return
      }

      // 初始化 Face Landmarker 服務
      // 注意：需要 face_landmarker.task 模型文件
      guard let modelPath = InferenceConfigurationManager.sharedInstance.faceLandmarkerModelPath else {
        result(FlutterError(code: "MODEL_NOT_FOUND", message: "Face landmarker model not found. Please add face_landmarker.task to the app bundle.", details: nil))
        return
      }

      guard let service = FaceLandmarkerService.stillImageLandmarkerService(
        modelPath: modelPath,
        minFaceDetectionConfidence: InferenceConfigurationManager.sharedInstance.minDetectionConfidence,
        minFacePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
        delegate: InferenceConfigurationManager.sharedInstance.delegate,
        outputFaceBlendshapes: false,
        outputFacialTransformationMatrixes: false
      ) else {
        result(FlutterError(code: "INIT_FAILED", message: "Failed to initialize FaceLandmarkerService", details: nil))
        return
      }

      // 執行關鍵點檢測
      guard let resultBundle = service.detect(image: uiImage) else {
        result(FlutterError(code: "DETECTION_FAILED", message: "No face landmark detection result", details: nil))
        return
      }

      // 提取關鍵點數據
      var allLandmarks: [[[Double]]] = [] // 每個臉的關鍵點列表
      var maxConfidence: Float = 0.0
      
      if let landmarkResult = resultBundle.faceLandmarkerResult {
        let faceLandmarks = landmarkResult.faceLandmarks
        
        for faceLandmark in faceLandmarks {
          var landmarks: [[Double]] = []
          
          for landmark in faceLandmark {
            // 每個關鍵點包含 x, y, z 坐標
            landmarks.append([
              Double(landmark.x),
              Double(landmark.y),
              Double(landmark.z ?? 0.0) // z 可能為 nil
            ])
          }
          
          allLandmarks.append(landmarks)
        }
        
        // 計算最高置信度（如果有檢測結果）
        if !faceLandmarks.isEmpty {
          maxConfidence = 1.0 // Face Landmarker 不直接提供置信度，使用 1.0 作為標記
        }
      }
      
      // 格式化輸出
      let inferenceTimeString = String(format: "%.2fms", resultBundle.inferenceTime)
      let confidenceString = String(format: "%.2f", maxConfidence * 100) + "%"
      
      // 返回結果
      result([
        "inferenceTime": inferenceTimeString,
        "confidence": confidenceString,
        "landmarks": allLandmarks, // 關鍵點坐標列表
        "faceCount": allLandmarks.count // 檢測到的人臉數量
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

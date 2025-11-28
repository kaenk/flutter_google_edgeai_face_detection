package com.example.flutter_face_detector

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.facedetector.FaceDetectorResult
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage


class FlutterFaceDetectorPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_face_detector")
        channel.setMethodCallHandler(this)
        applicationContext = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        val method = call.method

        if (method == "getPlatformVersion") {
            result.success("Android " + android.os.Build.VERSION.RELEASE)
            return
        }

        if (method == "faceDetectionFromImage") {
            val args = call.arguments
            if (args !is Map<*, *>) {
                result.error("ARG_ERROR", "Invalid arguments", null)
                return
            }

            val imageData = args["image"]
            if (imageData !is ByteArray) {
                result.error("NO_IMAGE", "No image data found", null)
                return
            }

            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Unable to decode image", null)
                return
            }

            val startTime = System.currentTimeMillis()
            val results = detectFaces(bitmap)
            val inferenceTime = System.currentTimeMillis() - startTime

            if (results == null) {
                result.error("DETECTION_FAILED", "Face detection failed", null)
                return
            }

            // ✅ 計算最高信心值（信心分數來自 detection.categories）
            var maxConfidence = 0.0f
            for (res in results) {
              for (detection in res.detections()) { // ✅ 加上 ()
                  val score = detection.categories().firstOrNull()?.score() ?: 0.0f // ✅ categories() 也一樣
                  if (score > maxConfidence) {
                      maxConfidence = score
                  }
              }
            }

            val inferenceTimeString = String.format("%.2fms", inferenceTime.toFloat())
            val confidenceString = String.format("%.2f%%", maxConfidence * 100)

            val response = HashMap<String, String>()
            response["inferenceTime"] = inferenceTimeString
            response["confidence"] = confidenceString

            result.success(response)
            return
        }

        if (method == "faceLandmarkDetectionFromImage") {
            val args = call.arguments
            if (args !is Map<*, *>) {
                result.error("ARG_ERROR", "Invalid arguments", null)
                return
            }

            val imageData = args["image"]
            if (imageData !is ByteArray) {
                result.error("NO_IMAGE", "No image data found", null)
                return
            }

            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Unable to decode image", null)
                return
            }

            val startTime = System.currentTimeMillis()
            val landmarkResult = detectFaceLandmarks(bitmap)
            val inferenceTime = System.currentTimeMillis() - startTime

            if (landmarkResult == null) {
                result.error("DETECTION_FAILED", "Face landmark detection failed", null)
                return
            }

            // 提取關鍵點數據
            val allLandmarks = mutableListOf<List<List<Double>>>()
            
            for (faceLandmark in landmarkResult.faceLandmarks()) {
                val landmarks = mutableListOf<List<Double>>()
                
                for (landmark in faceLandmark) {
                    // 每個關鍵點包含 x, y, z 坐標
                    landmarks.add(listOf(
                        landmark.x().toDouble(),
                        landmark.y().toDouble(),
                        (landmark.z() ?: 0.0f).toDouble()
                    ))
                }
                
                allLandmarks.add(landmarks)
            }

            val inferenceTimeString = String.format("%.2fms", inferenceTime.toFloat())
            val confidenceString = if (allLandmarks.isNotEmpty()) "100.00%" else "0.00%"

            val response = HashMap<String, Any>()
            response["inferenceTime"] = inferenceTimeString
            response["confidence"] = confidenceString
            response["landmarks"] = allLandmarks
            response["faceCount"] = allLandmarks.size

            result.success(response)
            return
        }

        result.notImplemented()
    }

    // ⭐ Mediapipe Tasks 臉部偵測
    private fun detectFaces(bitmap: Bitmap): List<FaceDetectorResult>? {
        return try {
            // ✅ 1. 載入 blaze_face_short_range.tflite
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("blaze_face_short_range.tflite")
                .build()

            // ✅ 2. 建立 FaceDetector options
            val options = FaceDetector.FaceDetectorOptions.builder()
                .setBaseOptions(baseOptions)
                .setMinDetectionConfidence(0.5f)
                .setRunningMode(RunningMode.IMAGE)
                .build()

            // ✅ 3. 建立 FaceDetector 實例
            val detector = FaceDetector.createFromOptions(applicationContext, options)


            // ✅ 4. 將 bitmap 轉為 MPImage
            val mpImage = BitmapImageBuilder(bitmap).build()

            // ✅ 5. 執行推論
            val result = detector.detect(mpImage)

            // ✅ 6. 關閉資源
            detector.close()

            // 回傳結果
            listOf(result)
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    // ⭐ Mediapipe Tasks 臉部關鍵點偵測
    private fun detectFaceLandmarks(bitmap: Bitmap): FaceLandmarkerResult? {
        return try {
            // ✅ 1. 載入 face_landmarker.task 模型
            // 注意：需要將 face_landmarker.task 文件放在 android/src/main/assets/ 目錄下
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("face_landmarker.task")
                .build()

            // ✅ 2. 建立 FaceLandmarker options
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setOutputFaceBlendshapes(false)
                .setOutputFacialTransformationMatrixes(false)
                .setRunningMode(RunningMode.IMAGE)
                .build()

            // ✅ 3. 建立 FaceLandmarker 實例
            val landmarker = FaceLandmarker.createFromOptions(applicationContext, options)

            // ✅ 4. 將 bitmap 轉為 MPImage
            val mpImage = BitmapImageBuilder(bitmap).build()

            // ✅ 5. 執行推論
            val result = landmarker.detect(mpImage)

            // ✅ 6. 關閉資源
            landmarker.close()

            // 回傳結果
            result
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

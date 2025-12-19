package com.example.flutter_face_detector

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.facedetector.FaceDetectorResult
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.framework.MediaPipeException
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import java.util.concurrent.atomic.AtomicBoolean


/**
 * Flutter Face Detector Plugin
 * 使用 MediaPipe Tasks Vision 0.10.26 进行人脸检测和关键点检测
 * 
 * 优化要点：
 * 1. 单例模式缓存 detector 实例以提高性能
 * 2. 线程安全的资源管理
 * 3. 完善的错误处理和日志记录
 * 4. 支持配置选项自定义
 */
class FlutterFaceDetectorPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    // 使用单例模式缓存 detector 实例以提高性能
    @Volatile
    private var faceDetector: FaceDetector? = null
    
    @Volatile
    private var faceLandmarker: FaceLandmarker? = null
    
    // 使用锁确保线程安全
    private val detectorLock = ReentrantLock()
    private val landmarkerLock = ReentrantLock()
    
    // 用于跟踪检测状态，防止并发调用导致崩溃
    private val isDetectingFaces = AtomicBoolean(false)
    private val isDetectingLandmarks = AtomicBoolean(false)
    
    // 配置常量
    companion object {
        private const val TAG = "FlutterFaceDetector"
        private const val DEFAULT_FACE_DETECTOR_MODEL = "blaze_face_short_range.tflite"
        private const val DEFAULT_FACE_LANDMARKER_MODEL = "face_landmarker.task"
        private const val DEFAULT_MIN_DETECTION_CONFIDENCE = 0.5f
        private const val DEFAULT_MIN_FACE_PRESENCE_CONFIDENCE = 0.5f
        private const val DEFAULT_MIN_TRACKING_CONFIDENCE = 0.5f
        private const val MAX_IMAGE_DIMENSION = 4096 // 最大图像尺寸，防止过大图像导致崩溃
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_face_detector")
        channel.setMethodCallHandler(this)
        applicationContext = flutterPluginBinding.applicationContext
        
        // 检查 OpenGL 支持（用于诊断）
        checkOpenGLSupport()
        
        // 设置全局异常处理器，捕获未处理的异常（包括 native 崩溃前的异常）
        setupUncaughtExceptionHandler()
    }
    
    /**
     * 检查设备信息（用于诊断问题）
     * 注意：不直接调用 OpenGL API，避免触发 native 崩溃
     */
    private fun checkOpenGLSupport() {
        try {
            val isEmulator = Build.FINGERPRINT.contains("generic", ignoreCase = true) || 
                            Build.FINGERPRINT.contains("unknown", ignoreCase = true) ||
                            Build.MODEL.contains("google_sdk", ignoreCase = true) ||
                            Build.MODEL.contains("Emulator", ignoreCase = true) ||
                            Build.MODEL.contains("Android SDK built for", ignoreCase = true) ||
                            Build.BRAND.contains("generic", ignoreCase = true)
            
            android.util.Log.i(TAG, "Device info: Model=${Build.MODEL}, Manufacturer=${Build.MANUFACTURER}, " +
                    "Brand=${Build.BRAND}, IsEmulator=$isEmulator, SDK=${Build.VERSION.SDK_INT}")
            
            if (isEmulator) {
                android.util.Log.w(TAG, "Running on emulator - OpenGL support may be limited. Using CPU delegate.")
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "Error checking device info", e)
        }
    }
    
    /**
     * 设置未捕获异常处理器，用于捕获可能的崩溃前异常
     */
    private fun setupUncaughtExceptionHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, exception ->
            if (thread.name.contains("mediapipe", ignoreCase = true)) {
                android.util.Log.e(TAG, "Uncaught exception in MediaPipe thread: ${thread.name}", exception)
                // 重置检测状态
                isDetectingFaces.set(false)
                isDetectingLandmarks.set(false)
            }
            // 调用默认处理器
            defaultHandler?.uncaughtException(thread, exception)
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "faceDetectionFromImage" -> {
                handleFaceDetection(call, result)
            }
            "faceLandmarkDetectionFromImage" -> {
                handleFaceLandmarkDetection(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 处理人脸检测请求
     */
    private fun handleFaceDetection(call: MethodCall, result: Result) {
        try {
            val args = call.arguments as? Map<*, *>
                ?: run {
                    android.util.Log.e(TAG, "Invalid arguments: null")
                    result.error("ARG_ERROR", "Invalid arguments", null)
                    return
                }

            val imageData = args["image"] as? ByteArray
                ?: run {
                    android.util.Log.e(TAG, "No image data found in arguments")
                    result.error("NO_IMAGE", "No image data found", null)
                    return
                }

            if (imageData.isEmpty()) {
                android.util.Log.e(TAG, "Empty image data")
                result.error("INVALID_IMAGE", "Empty image data", null)
                return
            }

            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                ?: run {
                    android.util.Log.e(TAG, "Unable to decode image from byte array")
                    result.error("INVALID_IMAGE", "Unable to decode image", null)
                    return
                }

            // 验证 bitmap 有效性
            if (bitmap.isRecycled) {
                android.util.Log.e(TAG, "Bitmap is recycled")
                result.error("INVALID_IMAGE", "Bitmap is recycled", null)
                return
            }
            
            // 验证图像尺寸，防止过大图像导致崩溃
            if (bitmap.width > MAX_IMAGE_DIMENSION || bitmap.height > MAX_IMAGE_DIMENSION) {
                android.util.Log.w(TAG, "Image too large: ${bitmap.width}x${bitmap.height}, max: ${MAX_IMAGE_DIMENSION}")
                result.error("INVALID_IMAGE", "Image dimensions too large: ${bitmap.width}x${bitmap.height}", null)
                return
            }
            
            // 检查是否正在检测，防止并发调用
            if (!isDetectingFaces.compareAndSet(false, true)) {
                android.util.Log.w(TAG, "Face detection already in progress, skipping")
                result.error("BUSY", "Face detection already in progress", null)
                return
            }

            val startTime = System.currentTimeMillis()
            val detectionResult = try {
                detectFaces(bitmap)
            } finally {
                // 确保重置状态
                isDetectingFaces.set(false)
            }
            val inferenceTime = System.currentTimeMillis() - startTime

            if (detectionResult == null) {
                android.util.Log.e(TAG, "Face detection returned null result")
                result.error("DETECTION_FAILED", "Face detection failed", null)
                return
            }

            // 计算最高置信度和所有检测结果
            var maxConfidence = 0.0f
            val detections = detectionResult.detections()
            
            for (detection in detections) {
                val categories = detection.categories()
                if (categories.isNotEmpty()) {
                    val score = categories[0].score()
                    if (score > maxConfidence) {
                        maxConfidence = score
                    }
                }
            }

            val response = hashMapOf<String, Any>(
                "inferenceTime" to String.format("%.2fms", inferenceTime.toFloat()),
                "confidence" to String.format("%.2f%%", maxConfidence * 100),
                "faceCount" to detections.size
            )

            android.util.Log.d(TAG, "Face detection successful: ${detections.size} faces, max confidence: $maxConfidence")
            result.success(response)
        } catch (e: MediaPipeException) {
            android.util.Log.e(TAG, "MediaPipe exception during face detection", e)
            result.error("MEDIAPIPE_ERROR", "MediaPipe error: ${e.message}", null)
        } catch (e: IllegalArgumentException) {
            android.util.Log.e(TAG, "Illegal argument during face detection", e)
            result.error("ARG_ERROR", "Invalid argument: ${e.message}", null)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Unexpected error during face detection", e)
            result.error("DETECTION_ERROR", "Face detection error: ${e.message}", null)
        }
    }

    /**
     * 处理人脸关键点检测请求
     */
    private fun handleFaceLandmarkDetection(call: MethodCall, result: Result) {
        try {
            val args = call.arguments as? Map<*, *>
                ?: run {
                    android.util.Log.e(TAG, "Invalid arguments: null")
                    result.error("ARG_ERROR", "Invalid arguments", null)
                    return
                }

            val imageData = args["image"] as? ByteArray
                ?: run {
                    android.util.Log.e(TAG, "No image data found in arguments")
                    result.error("NO_IMAGE", "No image data found", null)
                    return
                }

            if (imageData.isEmpty()) {
                android.util.Log.e(TAG, "Empty image data")
                result.error("INVALID_IMAGE", "Empty image data", null)
                return
            }

            val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                ?: run {
                    android.util.Log.e(TAG, "Unable to decode image from byte array")
                    result.error("INVALID_IMAGE", "Unable to decode image", null)
                    return
                }

            // 验证 bitmap 有效性
            if (bitmap.isRecycled) {
                android.util.Log.e(TAG, "Bitmap is recycled")
                result.error("INVALID_IMAGE", "Bitmap is recycled", null)
                return
            }
            
            // 验证图像尺寸，防止过大图像导致崩溃
            if (bitmap.width > MAX_IMAGE_DIMENSION || bitmap.height > MAX_IMAGE_DIMENSION) {
                android.util.Log.w(TAG, "Image too large: ${bitmap.width}x${bitmap.height}, max: ${MAX_IMAGE_DIMENSION}")
                result.error("INVALID_IMAGE", "Image dimensions too large: ${bitmap.width}x${bitmap.height}", null)
                return
            }
            
            // 检查是否正在检测，防止并发调用
            if (!isDetectingLandmarks.compareAndSet(false, true)) {
                android.util.Log.w(TAG, "Face landmark detection already in progress, skipping")
                result.error("BUSY", "Face landmark detection already in progress", null)
                return
            }

            val startTime = System.currentTimeMillis()
            val landmarkResult = try {
                detectFaceLandmarks(bitmap)
            } finally {
                // 确保重置状态
                isDetectingLandmarks.set(false)
            }
            val inferenceTime = System.currentTimeMillis() - startTime

            if (landmarkResult == null) {
                android.util.Log.e(TAG, "Face landmark detection returned null result")
                result.error("DETECTION_FAILED", "Face landmark detection failed", null)
                return
            }

            // 提取关键点数据
            val allLandmarks = mutableListOf<List<List<Double>>>()
            val faceLandmarks = landmarkResult.faceLandmarks()
            
            for (faceLandmark in faceLandmarks) {
                val landmarks = mutableListOf<List<Double>>()
                for (landmark in faceLandmark) {
                    landmarks.add(listOf(
                        landmark.x().toDouble(),
                        landmark.y().toDouble(),
                        (landmark.z() ?: 0.0f).toDouble()
                    ))
                }
                allLandmarks.add(landmarks)
            }

            val response = hashMapOf<String, Any>(
                "inferenceTime" to String.format("%.2fms", inferenceTime.toFloat()),
                "confidence" to if (allLandmarks.isNotEmpty()) "100.00%" else "0.00%",
                "landmarks" to allLandmarks,
                "faceCount" to allLandmarks.size
            )

            android.util.Log.d(TAG, "Face landmark detection successful: ${allLandmarks.size} faces, ${allLandmarks.firstOrNull()?.size ?: 0} landmarks per face")
            result.success(response)
        } catch (e: MediaPipeException) {
            android.util.Log.e(TAG, "MediaPipe exception during face landmark detection", e)
            result.error("MEDIAPIPE_ERROR", "MediaPipe error: ${e.message}", null)
        } catch (e: IllegalArgumentException) {
            android.util.Log.e(TAG, "Illegal argument during face landmark detection", e)
            result.error("ARG_ERROR", "Invalid argument: ${e.message}", null)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Unexpected error during face landmark detection", e)
            result.error("DETECTION_ERROR", "Face landmark detection error: ${e.message}", null)
        }
    }

    /**
     * 使用 MediaPipe Tasks Vision 进行人脸检测
     * 使用单例模式缓存 detector 实例以提高性能
     * 添加多层保护以防止 native 崩溃
     */
    private fun detectFaces(bitmap: Bitmap): FaceDetectorResult? {
        var detector: FaceDetector? = null
        return try {
            // 验证 detector 状态
            detector = getOrCreateFaceDetector() ?: run {
                android.util.Log.e(TAG, "Failed to create FaceDetector")
                return null
            }
            
            // 再次验证 detector 是否有效（防止在获取过程中被关闭）
            detectorLock.withLock {
                if (faceDetector != detector) {
                    android.util.Log.w(TAG, "Detector instance changed during detection")
                    return null
                }
            }

            // 验证 bitmap 状态
            if (bitmap.isRecycled) {
                android.util.Log.e(TAG, "Bitmap was recycled before detection")
                return null
            }

            // 将 bitmap 转换为 MPImage（可能抛出异常）
            val mpImage = try {
                BitmapImageBuilder(bitmap).build()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to create MPImage from bitmap", e)
                return null
            }

            // 执行推理 - 这是最可能崩溃的地方
            val result = try {
                detector.detect(mpImage)
            } catch (e: OutOfMemoryError) {
                android.util.Log.e(TAG, "OutOfMemoryError during face detection", e)
                // 尝试清理并返回 null
                System.gc()
                return null
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e(TAG, "Native library error during face detection", e)
                // 重置 detector，可能需要重新加载 native 库
                detectorLock.withLock {
                    try {
                        faceDetector?.close()
                    } catch (closeException: Exception) {
                        android.util.Log.w(TAG, "Error closing detector after native error", closeException)
                    }
                    faceDetector = null
                }
                return null
            }
            
            android.util.Log.v(TAG, "Face detection completed: ${result.detections().size} detections")
            result
        } catch (e: MediaPipeException) {
            android.util.Log.e(TAG, "MediaPipe exception during face detection", e)
            null
        } catch (e: IllegalStateException) {
            android.util.Log.e(TAG, "Illegal state during face detection (detector may be closed)", e)
            // 重置 detector 以便下次重新创建
            detectorLock.withLock {
                try {
                    faceDetector?.close()
                } catch (closeException: Exception) {
                    android.util.Log.w(TAG, "Error closing detector after IllegalStateException", closeException)
                }
                faceDetector = null
            }
            null
        } catch (e: Throwable) {
            // 捕获所有异常，包括 Error 类型（如 OutOfMemoryError）
            android.util.Log.e(TAG, "Unexpected throwable during face detection: ${e.javaClass.simpleName}", e)
            // 如果是严重错误，尝试重置 detector
            if (e is Error) {
                detectorLock.withLock {
                    try {
                        faceDetector?.close()
                    } catch (closeException: Exception) {
                        android.util.Log.w(TAG, "Error closing detector after Error", closeException)
                    }
                    faceDetector = null
                }
            }
            null
        }
    }

    /**
     * 使用 MediaPipe Tasks Vision 进行人脸关键点检测
     * 使用单例模式缓存 landmarker 实例以提高性能
     * 添加多层保护以防止 native 崩溃
     */
    private fun detectFaceLandmarks(bitmap: Bitmap): FaceLandmarkerResult? {
        var landmarker: FaceLandmarker? = null
        return try {
            // 验证 landmarker 状态
            landmarker = getOrCreateFaceLandmarker() ?: run {
                android.util.Log.e(TAG, "Failed to create FaceLandmarker")
                return null
            }
            
            // 再次验证 landmarker 是否有效（防止在获取过程中被关闭）
            landmarkerLock.withLock {
                if (faceLandmarker != landmarker) {
                    android.util.Log.w(TAG, "Landmarker instance changed during detection")
                    return null
                }
            }

            // 验证 bitmap 状态
            if (bitmap.isRecycled) {
                android.util.Log.e(TAG, "Bitmap was recycled before detection")
                return null
            }

            // 将 bitmap 转换为 MPImage（可能抛出异常）
            val mpImage = try {
                BitmapImageBuilder(bitmap).build()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to create MPImage from bitmap", e)
                return null
            }

            // 执行推理 - 这是最可能崩溃的地方（OpenGL 相关）
            val result = try {
                landmarker.detect(mpImage)
            } catch (e: OutOfMemoryError) {
                android.util.Log.e(TAG, "OutOfMemoryError during face landmark detection", e)
                // 尝试清理并返回 null
                System.gc()
                return null
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e(TAG, "Native library error during face landmark detection", e)
                // 重置 landmarker，可能需要重新加载 native 库
                landmarkerLock.withLock {
                    try {
                        faceLandmarker?.close()
                    } catch (closeException: Exception) {
                        android.util.Log.w(TAG, "Error closing landmarker after native error", closeException)
                    }
                    faceLandmarker = null
                }
                return null
            }
            
            android.util.Log.v(TAG, "Face landmark detection completed: ${result.faceLandmarks().size} faces")
            result
        } catch (e: MediaPipeException) {
            android.util.Log.e(TAG, "MediaPipe exception during face landmark detection", e)
            null
        } catch (e: IllegalStateException) {
            android.util.Log.e(TAG, "Illegal state during face landmark detection (landmarker may be closed)", e)
            // 重置 landmarker 以便下次重新创建
            landmarkerLock.withLock {
                try {
                    faceLandmarker?.close()
                } catch (closeException: Exception) {
                    android.util.Log.w(TAG, "Error closing landmarker after IllegalStateException", closeException)
                }
                faceLandmarker = null
            }
            null
        } catch (e: Throwable) {
            // 捕获所有异常，包括 Error 类型（如 OutOfMemoryError, UnsatisfiedLinkError）
            android.util.Log.e(TAG, "Unexpected throwable during face landmark detection: ${e.javaClass.simpleName}", e)
            // 如果是严重错误，尝试重置 landmarker
            if (e is Error) {
                landmarkerLock.withLock {
                    try {
                        faceLandmarker?.close()
                    } catch (closeException: Exception) {
                        android.util.Log.w(TAG, "Error closing landmarker after Error", closeException)
                    }
                    faceLandmarker = null
                }
            }
            null
        }
    }

    /**
     * 获取或创建 FaceDetector 实例（单例模式，线程安全）
     * 参考 MediaPipe 最佳实践：使用单例模式避免重复创建，提高性能
     */
    private fun getOrCreateFaceDetector(): FaceDetector? {
        // 快速路径：如果已经创建，直接返回
        faceDetector?.let { return it }

        return detectorLock.withLock {
            // 双重检查锁定：在获取锁后再次检查
            faceDetector?.let { return@withLock it }

            try {
                android.util.Log.d(TAG, "Creating FaceDetector instance...")
                
                // 显式设置使用 CPU delegate，避免 GPU/OpenGL 相关问题
                // 参考：https://ai.google.dev/edge/mediapipe/solutions/guide
                // 在模拟器或某些设备上，GPU 支持可能不完整，强制使用 CPU 更稳定
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath(DEFAULT_FACE_DETECTOR_MODEL)
                    .setDelegate(Delegate.CPU)  // 显式使用 CPU，避免 OpenGL 崩溃
                    .build()

                val options = FaceDetector.FaceDetectorOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinDetectionConfidence(DEFAULT_MIN_DETECTION_CONFIDENCE)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()
                
                android.util.Log.d(TAG, "FaceDetector configured with CPU delegate")

                val detector = FaceDetector.createFromOptions(applicationContext, options)
                faceDetector = detector
                android.util.Log.i(TAG, "FaceDetector created successfully")
                detector
            } catch (e: MediaPipeException) {
                android.util.Log.e(TAG, "MediaPipe exception while creating FaceDetector", e)
                null
            } catch (e: IllegalArgumentException) {
                android.util.Log.e(TAG, "Invalid argument while creating FaceDetector", e)
                null
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Unexpected exception while creating FaceDetector", e)
                null
            }
        }
    }

    /**
     * 获取或创建 FaceLandmarker 实例（单例模式，线程安全）
     * 参考 MediaPipe 最佳实践：使用单例模式避免重复创建，提高性能
     */
    private fun getOrCreateFaceLandmarker(): FaceLandmarker? {
        // 快速路径：如果已经创建，直接返回
        faceLandmarker?.let { return it }

        return landmarkerLock.withLock {
            // 双重检查锁定：在获取锁后再次检查
            faceLandmarker?.let { return@withLock it }

            try {
                android.util.Log.d(TAG, "Creating FaceLandmarker instance...")
                
                // 显式设置使用 CPU delegate，避免 GPU/OpenGL 相关问题
                // 参考：https://ai.google.dev/edge/mediapipe/solutions/guide
                // 在模拟器或某些设备上，GPU 支持可能不完整，强制使用 CPU 更稳定
                // 注意：FaceLandmarker 在某些情况下可能仍会使用 OpenGL 进行图像处理
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath(DEFAULT_FACE_LANDMARKER_MODEL)
                    .setDelegate(Delegate.CPU)  // 显式使用 CPU，避免 OpenGL 崩溃
                    .build()

                val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinFaceDetectionConfidence(DEFAULT_MIN_DETECTION_CONFIDENCE)
                    .setMinFacePresenceConfidence(DEFAULT_MIN_FACE_PRESENCE_CONFIDENCE)
                    .setMinTrackingConfidence(DEFAULT_MIN_TRACKING_CONFIDENCE)
                    .setOutputFaceBlendshapes(false)
                    .setOutputFacialTransformationMatrixes(false)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()
                
                android.util.Log.d(TAG, "FaceLandmarker configured with CPU delegate")

                val landmarker = FaceLandmarker.createFromOptions(applicationContext, options)
                faceLandmarker = landmarker
                android.util.Log.i(TAG, "FaceLandmarker created successfully")
                landmarker
            } catch (e: MediaPipeException) {
                android.util.Log.e(TAG, "MediaPipe exception while creating FaceLandmarker", e)
                null
            } catch (e: IllegalArgumentException) {
                android.util.Log.e(TAG, "Invalid argument while creating FaceLandmarker", e)
                null
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Unexpected exception while creating FaceLandmarker", e)
                null
            }
        }
    }

    /**
     * 释放资源
     * 参考 MediaPipe 最佳实践：确保正确关闭所有资源
     */
    private fun releaseResources() {
        detectorLock.withLock {
            try {
                faceDetector?.close()
                android.util.Log.d(TAG, "FaceDetector closed")
            } catch (e: Exception) {
                android.util.Log.w(TAG, "Error closing FaceDetector", e)
            } finally {
                faceDetector = null
            }
        }
        
        landmarkerLock.withLock {
            try {
                faceLandmarker?.close()
                android.util.Log.d(TAG, "FaceLandmarker closed")
            } catch (e: Exception) {
                android.util.Log.w(TAG, "Error closing FaceLandmarker", e)
            } finally {
                faceLandmarker = null
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.d(TAG, "Plugin detached from engine, releasing resources")
        channel.setMethodCallHandler(null)
        
        // 重置检测状态
        isDetectingFaces.set(false)
        isDetectingLandmarks.set(false)
        
        releaseResources()
    }
}

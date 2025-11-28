// Copyright 2023 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import MediaPipeTasksVision

// Initializes and calls the MediaPipe APIs for face landmark detection.
class FaceLandmarkerService: NSObject {
  
  var faceLandmarker: FaceLandmarker?
  private(set) var runningMode = RunningMode.image
  private var minFaceDetectionConfidence: Float = 0.5
  private var minFacePresenceConfidence: Float = 0.5
  private var minTrackingConfidence: Float = 0.5
  private var modelPath: String
  private var delegate: Delegate
  private var outputFaceBlendshapes: Bool = false
  private var outputFacialTransformationMatrixes: Bool = false

  // MARK: - Custom Initializer
  private init?(modelPath: String?, minFaceDetectionConfidence: Float, minFacePresenceConfidence: Float, minTrackingConfidence: Float, runningMode: RunningMode, delegate: Delegate, outputFaceBlendshapes: Bool, outputFacialTransformationMatrixes: Bool) {
    guard let modelPath = modelPath else { return nil }
    self.modelPath = modelPath
    self.minFaceDetectionConfidence = minFaceDetectionConfidence
    self.minFacePresenceConfidence = minFacePresenceConfidence
    self.minTrackingConfidence = minTrackingConfidence
    self.runningMode = runningMode
    self.delegate = delegate
    self.outputFaceBlendshapes = outputFaceBlendshapes
    self.outputFacialTransformationMatrixes = outputFacialTransformationMatrixes
    super.init()
    
    createFaceLandmarker()
  }

  private func createFaceLandmarker() {
    let faceLandmarkerOptions = FaceLandmarkerOptions()
    faceLandmarkerOptions.runningMode = runningMode
    faceLandmarkerOptions.minFaceDetectionConfidence = minFaceDetectionConfidence
    faceLandmarkerOptions.minFacePresenceConfidence = minFacePresenceConfidence
    faceLandmarkerOptions.minTrackingConfidence = minTrackingConfidence
    faceLandmarkerOptions.baseOptions.modelAssetPath = modelPath
    faceLandmarkerOptions.baseOptions.delegate = delegate
    faceLandmarkerOptions.outputFaceBlendshapes = outputFaceBlendshapes
    faceLandmarkerOptions.outputFacialTransformationMatrixes = outputFacialTransformationMatrixes
    
    do {
      faceLandmarker = try FaceLandmarker(options: faceLandmarkerOptions)
    }
    catch {
      print("Error creating FaceLandmarker: \(error)")
    }
  }

  // MARK: - Static Initializers
  static func stillImageLandmarkerService(
    modelPath: String?,
    minFaceDetectionConfidence: Float,
    minFacePresenceConfidence: Float,
    minTrackingConfidence: Float,
    delegate: Delegate,
    outputFaceBlendshapes: Bool = false,
    outputFacialTransformationMatrixes: Bool = false) -> FaceLandmarkerService? {
    let service = FaceLandmarkerService(
      modelPath: modelPath,
      minFaceDetectionConfidence: minFaceDetectionConfidence,
      minFacePresenceConfidence: minFacePresenceConfidence,
      minTrackingConfidence: minTrackingConfidence,
      runningMode: .image,
      delegate: delegate,
      outputFaceBlendshapes: outputFaceBlendshapes,
      outputFacialTransformationMatrixes: outputFacialTransformationMatrixes)
    
    return service
  }

  // MARK: - Detection Methods
  /**
   This method returns FaceLandmarkerResult and inferenceTime when receiving an image
   **/
  func detect(image: UIImage) -> LandmarkResultBundle? {
    guard let mpImage = try? MPImage(uiImage: image) else {
      return nil
    }
    
    do {
      let startDate = Date()
      let result = try faceLandmarker?.detect(image: mpImage)
      let inferenceTime = Date().timeIntervalSince(startDate) * 1000
      
      return LandmarkResultBundle(inferenceTime: inferenceTime, faceLandmarkerResult: result)
    } catch {
      print("Error detecting landmarks: \(error)")
      return nil
    }
  }
}

/// A result from the `FaceLandmarkerService`.
struct LandmarkResultBundle {
  let inferenceTime: Double
  let faceLandmarkerResult: FaceLandmarkerResult?
}


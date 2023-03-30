//
//  UIImage+Extension.swift
//  GlamTest
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import UIKit
import CoreML
import Vision
import CoreImage
import os

private let logger = Logger(subsystem: "Extension", category: "UIImage")

extension UIImage {
    func createPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        let data = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.interpolationQuality = .high
        context?.draw(self.cgImage!, in: CGRect(origin: .zero, size: size))

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    func resizedToSquare(size: CGSize = .init(width: 1024, height: 1024)) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        let aspectRatio = self.size.width / self.size.height
        let drawWidth = aspectRatio >= 1 ? size.width : size.width * aspectRatio
        let drawHeight = aspectRatio <= 1 ? size.height : size.height / aspectRatio
        let drawRect = CGRect(x: (size.width - drawWidth) / 2, y: (size.height - drawHeight) / 2, width: drawWidth, height: drawHeight)
        self.draw(in: drawRect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        logger.debug("\(resizedImage.size.debugDescription)")
        return resizedImage
    }

    // I have to admit that the object extraction feature works pretty bad with both given dataset and a model
    // yet I'm stating that this is the model scope of responsibility, sice as long as I see its preformance to detect this kind of objects placed in that environment is unstatisfailable.
    // Therefore model is the one what has to be improved not the app logic related to it.
    func applyHeatMap(heatMap: UIImage, threshold: CGFloat = 0.5) -> UIImage? {
        guard let imageCI = CIImage(image: self),
              let heatMapCI = CIImage(image: heatMap),
              self.size == heatMap.size else {
            print("Failed on imageRef")
            return nil
        }

        let thresholdFilter = CIFilter(name: "CIColorThreshold")!
        thresholdFilter.setValue(heatMapCI, forKey: kCIInputImageKey)
        thresholdFilter.setValue(threshold, forKey: "inputThreshold")

        let thresholdedImage = thresholdFilter.outputImage!

        let blendFilter = CIFilter(name: "CIBlendWithMask")!
        blendFilter.setValue(imageCI, forKey: kCIInputImageKey)
        blendFilter.setValue(thresholdedImage, forKey: kCIInputMaskImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)

        let outputImage = blendFilter.outputImage!

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("Failed to create CGImage")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Process image with ML model
    ///
    /// Image on what this method called should be square.
    ///
    /// - Parameter modelName: "mlmodelc" model
    /// - Returns: model output
    func processImage(with modelName: String) async -> UIImage? {
        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!
        let model = try! VNCoreMLModel(for: MLModel(contentsOf: modelURL))

        let resizedImage = self

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { (request, error) in
                if let error = error {
                    print("Error processing image: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = request.results as? [VNPixelBufferObservation],
                      let mask = results.first?.pixelBuffer  else {
                    continuation.resume(returning: nil)
                    return
                }

                if let maskImage = mask.toUIImage() {
                    continuation.resume(returning: maskImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            // Create a request handler and perform the request
            let handler = VNImageRequestHandler(cgImage: resizedImage.cgImage!, options: [:])
            try! handler.perform([request])
        }
    }
}

extension Array where Element == UIImage {
    var withInsertedMLProcessedFrames: [UIImage] {
        get async {
            var resultImages: [UIImage] = []

            for imageToProcess in self {
                let resizedImage = imageToProcess.resizedToSquare()
                if resultImages.isEmpty {
                    resultImages.append(resizedImage)
                } else {
                    let heatmap = await resizedImage.processImage(with: "segmentation_8bit")!
                    let extractedImage = resizedImage.applyHeatMap(heatMap: heatmap)
                    resultImages.append(extractedImage!)
                    resultImages.append(resizedImage)
                }
            }
            return resultImages
        }
    }
}


extension CVPixelBuffer {
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

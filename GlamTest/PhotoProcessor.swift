//
//  PhotoProcessor.swift
//  GlamTest
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import UIKit
import CoreML
import Vision
import os

private let logger = Logger(subsystem: "Services", category: "ImageProcessor")

private let defaultImageSize: CGSize = .init(width: 1024, height: 1024)

class ImageProcessor {
    func processImage(inputImage: UIImage, modelName: String) async -> UIImage? {

        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!
        let model = try! VNCoreMLModel(for: MLModel(contentsOf: modelURL))

        let resizedImage = inputImage.resizedToSquare(size: defaultImageSize)

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { (request, error) in
                if let error = error {
                    print("Error processing image: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                // Process the results
                guard let results = request.results as? [VNPixelBufferObservation],
                        let mask = results.first?.pixelBuffer  else {
                    continuation.resume(returning: nil)
                    return
                }

                // Convert the mask pixel buffer to a UIImage and flip it back.
                if let maskImage = mask.toUIImage() {
                    // Extract object from Image
                    if let extractedObjectImage = resizedImage.extractObjectUsingMask(maskImage: maskImage) {
                        continuation.resume(returning: extractedObjectImage)
                    } else {
                        continuation.resume(returning: nil)
                    }
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

extension UIImage {
    func resizedToSquare(size: CGSize) -> UIImage {
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

    func extractObjectUsingMask(maskImage: UIImage) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, true, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Draw the original image
        draw(at: .zero)

        // Apply the mask using the kCGBlendModeDestinationIn blend mode
        context.setBlendMode(.destinationIn)
        maskImage.draw(in: CGRect(origin: .zero, size: size))

        // Get the resulting image
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resultImage
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

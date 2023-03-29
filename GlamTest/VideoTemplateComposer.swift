//
//  VideoTemplateProcessor.swift
//  GlamTest
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import UIKit
import AVFoundation
import CoreML
import Vision
import os

private let logger = Logger(subsystem: "Services", category: "VideoTemplateComposer")

class VideoTemplateComposer {
    // Later make something cooler.
    private let outputSize = CGSize(width: 1024, height: 1024)

    private func createPixelBuffer(from image: UIImage?, size: CGSize) -> CVPixelBuffer? {
        guard let image = image else { return nil }

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
        context?.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    func appendPixelBuffers(writerInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, frameDuration: CMTime, images: [UIImage], currentFrame: Int) async -> Bool {
        if writerInput.isReadyForMoreMediaData && currentFrame < images.count {

            logger.debug("Processing \(currentFrame)")

            let image = images[currentFrame]
            if let pixelBuffer = createPixelBuffer(from: image, size: outputSize) {
                logger.debug("Appending pixelBuffer for frame \(currentFrame)")
                adaptor.append(pixelBuffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(currentFrame)))
                let nextFrame = currentFrame + 1
                return await appendPixelBuffers(writerInput: writerInput, adaptor: adaptor, frameDuration: frameDuration, images: images, currentFrame: nextFrame)
            }
        } else if currentFrame >= images.count {
            logger.debug("Reached the end of images list.")
            return true
        }
        logger.error("Failed to appending pixelBuffer for frame \(currentFrame)")
        return false
    }

    func processVideoFrames(images: [UIImage]) async -> URL? {
        guard !images.isEmpty else {
            logger.error("Failed: no images provided.")
            return nil
        }

        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "output.mp4")

        try? FileManager.default.removeItem(at: outputFileURL)

        let videoWriter = try! AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = true
        videoWriter.add(videoWriterInput)

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 1)
        let initialFrame = 0

        if await appendPixelBuffers(writerInput: videoWriterInput, adaptor: pixelBufferAdaptor, frameDuration: frameDuration, images: images, currentFrame: initialFrame) {
            videoWriterInput.markAsFinished()
            await videoWriter.finishWriting()
            if videoWriter.status == .completed {
                logger.debug("Proceed successfully.")
                return outputFileURL
            }
        }
        logger.error("Failed to appendPixelBuffers")
        return nil
    }
}

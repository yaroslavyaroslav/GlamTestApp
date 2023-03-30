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
    private let outputSize: CGSize

    init(outputSize: CGSize) {
        self.outputSize = outputSize
    }

    func appendPixelBuffers(writerInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, frameDuration: CMTime, images: [UIImage], currentFrame: Int, lastImage: UIImage? = nil) async -> Bool {
        if writerInput.isReadyForMoreMediaData && currentFrame < images.count {

            logger.debug("Processing \(currentFrame)")

            var image = images[currentFrame]

            if let lastImage = lastImage {
                UIGraphicsBeginImageContextWithOptions(outputSize, false, 1)
                lastImage.draw(at: .zero)
                image.draw(at: .zero, blendMode: .normal, alpha: 1.0)
                image = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
            }

            if let pixelBuffer = image.createPixelBuffer(size: outputSize) {
                logger.debug("Appending pixelBuffer for frame \(currentFrame)")
                adaptor.append(pixelBuffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(currentFrame)))
                let nextFrame = currentFrame + 1

                return await appendPixelBuffers(writerInput: writerInput, adaptor: adaptor, frameDuration: frameDuration, images: images, currentFrame: nextFrame, lastImage: image)
            }
        } else if currentFrame >= images.count {
            logger.debug("Reached the end of images list.")
            return true
        }
        logger.error("Failed to appending pixelBuffer for frame \(currentFrame)")
        return false
    }

    func processVideoFrames(images: [UIImage]) async -> AVAsset? {
        guard !images.isEmpty else {
            logger.error("Failed: no images provided.")
            return nil
        }

        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "\(UUID()).mp4")

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

        let frameDuration = CMTime(value: 2, timescale: 3)
        let initialFrame = 0

        let videoAsset: AVAsset

        if await appendPixelBuffers(writerInput: videoWriterInput, adaptor: pixelBufferAdaptor, frameDuration: frameDuration, images: images, currentFrame: initialFrame) {
            videoWriterInput.markAsFinished()
            await videoWriter.finishWriting()
            if videoWriter.status == .completed {
                logger.debug("Video processing completed.")
                videoAsset = AVAsset(url: outputFileURL)
            } else {
                logger.error("Failed to appendPixelBuffers")
                return nil
            }
        } else {
            logger.error("Failed to appendPixelBuffers")
            return nil
        }

        // Load audio asset and merge it with the video
        guard let audioAsset = AVAsset.loadAudioAsset(),
              let outputAsset = await videoAsset.mergeVideoAsset(with: audioAsset) else {
            logger.error("Failed to merge audio with video.")
            return nil
        }

        logger.debug("Audio merged successfully.")
        return outputAsset
    }
}

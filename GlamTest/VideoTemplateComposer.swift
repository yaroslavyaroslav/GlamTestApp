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

            if let pixelBuffer = createPixelBuffer(from: image, size: outputSize) {
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
                    logger.debug("Video processing completed.")

                    // Load audio asset and merge it with the video
                    guard let audioAsset = loadAudioAsset(),
                          let outputWithAudioURL = merge(videoURL: outputFileURL, audioAsset: audioAsset) else {
                        logger.error("Failed to merge audio with video.")
                        return nil
                    }

                    logger.debug("Audio merged successfully.")
                    return outputWithAudioURL
                }
            }
        logger.error("Failed to appendPixelBuffers")
        return nil
    }

    func merge(videoURL: URL, audioAsset: AVAsset) -> URL? {
        let mixComposition = AVMutableComposition()

        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset,
              let videoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }

        do {
            try videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
            try audioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: audioAsset.tracks(withMediaType: .audio)[0], at: .zero)
        } catch {
            logger.error("Error merging video and audio tracks: \(error)")
            return nil
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "output_with_audio.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let assetExport = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }

        assetExport.outputFileType = .mp4
        assetExport.outputURL = outputURL
        assetExport.shouldOptimizeForNetworkUse = true

        let semaphore = DispatchSemaphore(value: 0)
        var exportSuccess = false

        assetExport.exportAsynchronously {
            if assetExport.status == .completed {
                exportSuccess = true
            } else {
                logger.error("Failed to export merged video and audio: \(String(describing: assetExport.error))")
            }
            semaphore.signal()
        }

        semaphore.wait()

        return exportSuccess ? outputURL : nil
    }

    func loadAudioAsset() -> AVAsset? {
        guard let audioURL = Bundle.main.url(forResource: "music", withExtension: "aac") else {
            logger.error("Failed to find the audio file in resources.")
            return nil
        }
        return AVAsset(url: audioURL)
    }
}

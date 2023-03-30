//
//  AVAsset+Extension.swift
//  GlamTest
//
//  Created by Yaroslav Yashin on 2023-03-30.
//

import AVFoundation
import CoreML
import Vision
import os

private let logger = Logger(subsystem: "Extension", category: "AVAsset")

extension AVAsset {
    static func loadAudioAsset() -> AVAsset? {
        guard let audioURL = Bundle.main.url(forResource: "music", withExtension: "aac") else {
            logger.error("Failed to find the audio file in resources.")
            return nil
        }
        return AVAsset(url: audioURL)
    }

    func saveTo(file: URL) -> Bool {
        try? FileManager.default.removeItem(at: file)

        guard let exportSession = AVAssetExportSession(asset: self, presetName: AVAssetExportPresetHighestQuality) else {
            logger.error("Failed to create export session.")
            return false
        }

        exportSession.outputFileType = .mp4
        exportSession.outputURL = file

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                logger.debug("Export completed successfully.")
                success = true
            case .failed:
                logger.error("Export failed: \(String(describing: exportSession.error))")
            case .cancelled:
                logger.error("Export cancelled.")
            default:
                break
            }
            semaphore.signal()
        }

        semaphore.wait()
        return success
    }


    /// Merge video asset with audio
    ///
    /// Should be called only on video asset
    ///
    /// - Parameter audioAsset: audio asset
    /// - Returns: Video asset merged with audio
    func mergeVideoAsset(with audioAsset: AVAsset) async -> AVAsset? {
        let mixComposition = AVMutableComposition()

        guard let videoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }

        do {
            try await videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.load(.duration)), of: self.loadTracks(withMediaType: .video)[0], at: .zero)
            try await audioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.load(.duration)), of: audioAsset.loadTracks(withMediaType: .audio)[0], at: .zero)
        } catch {
            logger.error("Error merging video and audio tracks: \(error)")
            return nil
        }

        return mixComposition
    }
}

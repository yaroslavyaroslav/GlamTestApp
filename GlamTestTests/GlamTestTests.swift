//
//  GlamTestTests.swift
//  GlamTestTests
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import XCTest
@testable import GlamTest

final class GlamTestTests: XCTestCase {

    let imageNames = ["image-0", "image-1", "image-2", "image-3", "image-4", "image-5", "image-6", "image-7"]
    let modelName = "segmentation_8bit"

    lazy var initialImages: [UIImage] = {
        imageNames.compactMap { UIImage(named: $0, in: Bundle.main, compatibleWith: nil) }
    }()

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testProcessVideoFrames() async {
        XCTAssert(initialImages.count == imageNames.count, "Failed to load images from asset catalog")

        let expectation = self.expectation(description: "Video processing completed")

        let expandedImages = await initialImages.withInsertedMLProcessedFrames

        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "output.mp4")

        let originalSize = initialImages.first!.size

        let processedSize = initialImages.first!.resizedToSquare().scaleToOriginalRatio(size: originalSize).size

        let videoComposer = VideoTemplateComposer(outputSize: initialImages.first!.size)
        if let videoAsset = await videoComposer.processVideoFrames(images: expandedImages) {
            if videoAsset.saveTo(file: outputFileURL) {
                print("result: \(outputFileURL.absoluteString)")
                expectation.fulfill()
            } else {
                XCTFail("Video processing failed")
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 30)
    }

    func testProcessPhoto() async {
        let appendedImages = await initialImages.withInsertedMLProcessedFrames

        for (index, image) in appendedImages.enumerated() {
            print(saveImageToTmpFolder(image: image, filename: "image-\(index)"))
        }
    }

    func testProcessHeatmap() async {
        for (index, image) in initialImages.enumerated() {
            let resizedImage = image.resizedToSquare()
            let heatmap = await resizedImage.processImage(with: "segmentation_8bit")!
            print(saveImageToTmpFolder(image: heatmap, filename: "heatmap-\(index)"))
        }
    }
}


fileprivate func saveImageToTmpFolder(image: UIImage, filename: String) -> URL? {
    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "\(filename).jpg")
    guard let imageData = image.jpegData(compressionQuality: 1.0) else { return nil }

    do {
        try imageData.write(to: fileURL)
        print("Image saved to: \(fileURL)")
        return fileURL
    } catch {
        print("Error saving image to file: \(error.localizedDescription)")
        return nil
    }
}

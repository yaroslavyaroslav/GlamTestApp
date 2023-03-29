//
//  GlamTestTests.swift
//  GlamTestTests
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import XCTest
@testable import GlamTest

final class GlamTestTests: XCTestCase {

    lazy var videoProcessor: VideoTemplateComposer = VideoTemplateComposer()
    lazy var imageProcessor: ImageProcessor = ImageProcessor()
    let imageNames = ["image-0", "image-1", "image-2", "image-3", "image-4", "image-5", "image-5", "image-6", "image-7"]
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

        let expandedImages = await appendVideoWithMLProcessedFrames(images: initialImages)

        if let outputURL = await videoProcessor.processVideoFrames(images: expandedImages) {
            print("result: \(outputURL.absoluteString)")
            expectation.fulfill()
        } else {
            XCTFail("Video processing failed")
            expectation.fulfill()
            return
        }

        await fulfillment(of: [expectation], timeout: 30)
    }

    func testProcessPhoto() async {
        for (index, image) in initialImages.enumerated() {
            let processedImage = await imageProcessor.processImage(inputImage: image, modelName: modelName)
            print(saveImageToTmpFolder(image: processedImage!, filename: String(index)))
        }
    }
}


fileprivate func saveImageToTmpFolder(image: UIImage, filename: String) -> URL? {
    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "image-\(filename).jpg")
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

fileprivate func appendVideoWithMLProcessedFrames(images: [UIImage]) async -> [UIImage] {
    var resultImages: [UIImage] = []

    for imageToProcess in images {
        if resultImages.isEmpty {
            resultImages.append(imageToProcess)
        } else {
            let extractedObjectImage = await ImageProcessor().processImage(inputImage: imageToProcess, modelName: "segmentation_8bit")!
            resultImages.append(extractedObjectImage)
            resultImages.append(imageToProcess)
        }
    }
    return resultImages
}


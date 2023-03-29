//
//  GlamTestTests.swift
//  GlamTestTests
//
//  Created by Yaroslav Yashin on 2023-03-29.
//

import XCTest
@testable import GlamTest

final class GlamTestTests: XCTestCase {

    lazy var videoProcessor: VideoTemplateProcessor = VideoTemplateProcessor()
    let imageNames = ["image-0", "image-1", "image-2", "image-3", "image-4", "image-5", "image-5", "image-6", "image-7"]

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testProcessVideoFrames() async {
        let bundle = Bundle.main
        let imageNames = ["image-0", "image-1", "image-2", "image-3", "image-4", "image-5", "image-6", "image-7"]

        let images = imageNames.compactMap { UIImage(named: $0, in: bundle, compatibleWith: nil) }
        XCTAssert(images.count == imageNames.count, "Failed to load images from asset catalog")

        let expectation = self.expectation(description: "Video processing completed")

        if let outputURL = await videoProcessor.processVideoFrames(imageNames: imageNames) {
            print("result: \(outputURL.absoluteString)")
            expectation.fulfill()
        } else {
            XCTFail("Video processing failed")
            expectation.fulfill()
            return
        }

        await fulfillment(of: [expectation], timeout: 30)
    }
}

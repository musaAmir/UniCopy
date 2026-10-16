import XCTest
import AppKit
@testable import UniCopyCore

final class CaptureTests: XCTestCase {
    func testSelectionSupportsEveryDragDirection() {
        let expected = CGRect(x:20,y:30,width:80,height:120)
        let bounds = CGRect(x:0,y:0,width:1000,height:1000)
        for pair in [(CGPoint(x:20,y:30),CGPoint(x:100,y:150)),(CGPoint(x:100,y:150),CGPoint(x:20,y:30)),(CGPoint(x:20,y:150),CGPoint(x:100,y:30))] {
            XCTAssertEqual(CaptureGeometry.selection(from:pair.0,to:pair.1,bounds:bounds),expected)
        }
    }
    func testSelectionClampsToTheChosenDisplayAndRejectsClicks() {
        XCTAssertEqual(CaptureGeometry.selection(from:CGPoint(x:50,y:50),to:CGPoint(x:-20,y:120),bounds:CGRect(x:0,y:0,width:100,height:100)),CGRect(x:0,y:50,width:50,height:50))
        XCTAssertNil(CaptureGeometry.selection(from:.zero,to:CGPoint(x:2,y:2),bounds:CGRect(x:0,y:0,width:100,height:100)))
    }
    func testCaptureCoordinatesAreDisplayLocalAndTopDown() {
        XCTAssertEqual(CaptureGeometry.sourceRect(selection:CGRect(x:100,y:200,width:300,height:250),screenHeight:1000),CGRect(x:100,y:550,width:300,height:250))
    }
    func testRetinaAndLargeCapturesHaveBoundedDimensions() {
        XCTAssertEqual(CaptureGeometry.pixelSize(points:CGSize(width:800,height:600),scale:2),CGSize(width:1600,height:1200))
        let size = CaptureGeometry.pixelSize(points:CGSize(width:8000,height:4000),scale:2)
        XCTAssertEqual(size,CGSize(width:4096,height:2048))
    }
    func fixture(text: Bool) -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1000,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        NSColor.white.setFill(); CGRect(x:0,y:0,width:1000,height:300).fill()
        if text {
            let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:48),.foregroundColor:NSColor.black]
            ("Invoice 1042" as NSString).draw(at:CGPoint(x:60,y:180),withAttributes:attrs)
            ("Total 123.45" as NSString).draw(at:CGPoint(x:60,y:80),withAttributes:attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
    func testRealVisionRecognizesSyntheticInvoice() throws {
        let text = try OCRService.recognize(fixture(text:true))
        XCTAssertTrue(text.contains("Invoice 1042"),text)
        XCTAssertTrue(text.contains("123.45"),text)
    }
    func testBlankImageDoesNotInventText() throws {
        XCTAssertEqual(try OCRService.recognize(fixture(text:false)),"")
    }
}

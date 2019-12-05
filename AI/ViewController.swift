//
//  ViewController.swift
//  AI
//
//  Created by Bruno Pastre on 05/12/19.
//  Copyright © 2019 Bruno Pastre. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var classLabel: UILabel!
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var classifyButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    
    var classification: String? = nil
    private var strokes: [CGMutablePath] = []
    private var currentStroke: CGMutablePath? { return strokes.last }
    private var imageViewSize: CGSize { return imageView.frame.size }
    private let classifier = DrawingClassifierModel()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        undoButton.disable()
        classifyButton.disable()
    }

    @IBAction func classify(_ sender: Any) {
        self.classify()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>,
        with event: UIEvent?) {

        guard let touch = touches.first else { return }

        let newStroke = CGMutablePath()
        newStroke.move(to: touch.location(in: imageView))
        strokes.append(newStroke)
        refresh()
    }
    

    override func touchesMoved(_ touches: Set<UITouch>,
        with event: UIEvent?) {

        guard let touch = touches.first,
            let currentStroke = self.currentStroke else {
                return
        }

        currentStroke.addLine(to: touch.location(in: imageView))
        refresh()
    }

    // stroke ended
    override func touchesEnded(_ touches: Set<UITouch>,
        with event: UIEvent?) {

        guard let touch = touches.first,
            let currentStroke = self.currentStroke else {
                return
        }

        currentStroke.addLine(to: touch.location(in: imageView))
        refresh()
    }

    func undo() {
        let _ = strokes.removeLast()
        refresh()
    }
    // clear all strokes
    func clear() {
        strokes = []
        classification = nil
        refresh()
    }
    
    func refresh() {
        if self.strokes.isEmpty { self.imageView.image = nil }

        let drawing = makeImage(from: self.strokes)
        self.imageView.image = drawing

        if classification != nil {
            undoButton.disable()
            clearButton.enable()
            classifyButton.disable()
        } else if !strokes.isEmpty {
            undoButton.enable()
            clearButton.enable()
            classifyButton.enable()
        } else {
            undoButton.disable()
            clearButton.disable()
            classifyButton.disable()
        }

        classLabel.text = classification ?? ""
    }
    
    func makeImage(from strokes: [CGMutablePath]) -> UIImage? {
        let image = CGContext.create(size: imageViewSize) { context in
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(8.0)
            context.setLineJoin(.round)
            context.setLineCap(.round)

            for stroke in strokes {
                context.beginPath()
                context.addPath(stroke)
                context.strokePath()
            }
        }

        return image
    }
    
    func classify() {
        guard let grayscaleImage =
            imageView.image?.applying(filter: .noir) else {
                return
        }
        
        
        classifier.classify(grayscaleImage.scaledTo(size: CGSize(width: 28, height: 28))) { result in
            self.classification = result?.icon

            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

}

extension CGContext {
    static func create(size: CGSize,
        action: (inout CGContext) -> ()) -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)

        guard var context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        action(&context)

        let result = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return result
    }
}
extension UIButton {
    func enable() {
        self.isEnabled = true
        self.backgroundColor = UIColor.systemBlue
    }

    func disable() {
        self.isEnabled = false
        self.backgroundColor = UIColor.lightGray
    }
}


extension UIImage {

    func resize(to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: newSize.width, height: newSize.height), true, 1.0)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        UIColor.white.setFill()
        UIRectFill(rect)
        self.draw(in: rect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return resizedImage
    }

    func cropToSquare() -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }
        var imageHeight = self.size.height
        var imageWidth = self.size.width

        if imageHeight > imageWidth {
            imageHeight = imageWidth
        }
        else {
            imageWidth = imageHeight
        }

        let size = CGSize(width: imageWidth, height: imageHeight)

        let x = ((CGFloat(cgImage.width) - size.width) / 2).rounded()
        let y = ((CGFloat(cgImage.height) - size.height) / 2).rounded()

        let cropRect = CGRect(x: x, y: y, width: size.height, height: size.width)
        if let croppedCgImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCgImage, scale: 0, orientation: self.imageOrientation)
        }

        return nil
    }

    func pixelBuffer() -> CVPixelBuffer? {
        let width = self.size.width
        let height = self.size.height
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(width),
                                         Int(height),
                                         kCVPixelFormatType_OneComponent8,
                                         attrs,
                                         &pixelBuffer)

        guard let resultPixelBuffer = pixelBuffer, status == kCVReturnSuccess else {
            return nil
        }

        CVPixelBufferLockBaseAddress(resultPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(resultPixelBuffer)

        let rgbColorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: pixelData,
                                      width: Int(width),
                                      height: Int(height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(resultPixelBuffer),
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                                        return nil
        }

        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(resultPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return resultPixelBuffer
    }
}

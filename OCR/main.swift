//
//  main.swift
//  OCR
//
//  Created by xulihang on 2023/1/1.
//

import Vision
import Cocoa

var MODE = VNRequestTextRecognitionLevel.accurate // or .fast
var USE_LANG_CORRECTION = false
var REVISION:Int

if #available(macOS 13, *) {
    REVISION = VNRecognizeTextRequestRevision3
} else if #available(macOS 11, *) {
    REVISION = VNRecognizeTextRequestRevision2
}else{
    REVISION = VNRecognizeTextRequestRevision1
}

func main(args: [String]) -> Int32 {
    
    if CommandLine.arguments.count == 2 {
        if args[1] == "--langs" {
            let request = VNRecognizeTextRequest.init()
            request.revision = REVISION
            request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
            let langs = try? request.supportedRecognitionLanguages()
            for lang in langs! {
                print(lang)
            }
        }
        return 0
    }else if CommandLine.arguments.count == 6 {
        let (language, fastmode, languageCorrection, src, dst) = (args[1], args[2],args[3],args[4],args[5])
        let substrings = language.split(separator: ",")
        var languages:[String] = []
        for substring in substrings {
            languages.append(String(substring))
        }
        if fastmode == "true" {
            MODE = VNRequestTextRecognitionLevel.fast
        }else{
            MODE = VNRequestTextRecognitionLevel.accurate
        }
        
        if languageCorrection == "true" {
            USE_LANG_CORRECTION = true
        }else{
            USE_LANG_CORRECTION = false
        }

        guard let img = NSImage(byReferencingFile: src) else {
            fputs("Error: failed to load image '\(src)'\n", stderr)
            return 1
        }
        guard let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("Error: failed to convert NSImage to CGImage for '\(src)'\n", stderr)
            return 1
        }


        let request = VNRecognizeTextRequest { (request, error) in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            var dict:[String:Any] = [:]
            var lines:[Any] = []
            var allText = ""
            var index = 0
            for observation in observations {
                // Find the top observation.
                var line:[String:Any] = [:]
                let candidate = observation.topCandidates(1).first
                let string = candidate?.string
                let confidence = candidate?.confidence
                // Find the bounding-box observation for the string range.
                let stringRange = string!.startIndex..<string!.endIndex
                let boxObservation = try? candidate?.boundingBox(for: stringRange)
                
                // Get the normalized CGRect value.
                let boundingBox = boxObservation?.boundingBox ?? .zero
                
                line["x0"] = Int((boxObservation?.topLeft.x ?? 0) * CGFloat(imgRef.width))
                line["y0"] = Int(CGFloat(imgRef.height) - (boxObservation?.topLeft.y ?? 0) * CGFloat(imgRef.height))
                line["x1"] = Int((boxObservation?.topRight.x ?? 0) * CGFloat(imgRef.width))
                line["y1"] = Int(CGFloat(imgRef.height) - (boxObservation?.topRight.y ?? 0) * CGFloat(imgRef.height))
                line["x2"] = Int((boxObservation?.bottomRight.x ?? 0) * CGFloat(imgRef.width))
                line["y2"] = Int(CGFloat(imgRef.height) - (boxObservation?.bottomRight.y ?? 0) * CGFloat(imgRef.height))
                line["x3"] = Int((boxObservation?.bottomLeft.x ?? 0) * CGFloat(imgRef.width))
                line["y3"] = Int(CGFloat(imgRef.height) - (boxObservation?.bottomLeft.y ?? 0) * CGFloat(imgRef.height))
                
                // Convert the rectangle from normalized coordinates to image coordinates.
                let rect = VNImageRectForNormalizedRect(boundingBox,
                                                        Int(imgRef.width),
                                                        Int(imgRef.height))

                
                line["text"] = string ?? ""
                line["confidence"] = confidence ?? ""
                line["x"] = Int(rect.minX)
                line["width"] = Int(rect.size.width)
                line["y"] = Int(CGFloat(imgRef.height) - rect.minY - rect.size.height)
                line["height"] = Int(rect.size.height)
                lines.append(line)
                allText = allText + (string ?? "")
                index = index + 1
                if index != observations.count {
                   allText = allText + "\n"
                }
            }
            dict["lines"] = lines
            dict["text"] = allText
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
            let jsonString = String(data: data!,
                                    encoding: .utf8) ?? "[]"
            try? jsonString.write(to: URL(fileURLWithPath: dst), atomically: true, encoding: String.Encoding.utf8)
        }
        request.recognitionLevel = MODE
        request.usesLanguageCorrection = USE_LANG_CORRECTION
        request.revision = REVISION
        request.recognitionLanguages = languages
        //request.minimumTextHeight = 0
        //request.customWords = [String]
        try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])

        return 0
    }else{
        print("""
              usage:
                language fastmode languageCorrection image_path output_path
                --langs: list suppported languages
              
              example:
                macOCR en false true ./image.jpg out.json
              """)
        return 1
    }
}



exit(main(args: CommandLine.arguments))

//
//  main.swift
//  OCR
//
//  Created by xulihang on 2023/1/1.
//

import Vision
import VisionKit
import Cocoa
import ObjectiveC.runtime

var MODE = VNRequestTextRecognitionLevel.accurate // or .fast
var USE_LANG_CORRECTION = false
var WORD_LEVEL = false // 新增：是否启用单词级别识别
var USE_LIVETEXT = false // 新增：是否使用 Live Text (VisionKit) 而不是 VNRecognizeTextRequest
var REVISION:Int

if #available(macOS 13, *) {
    REVISION = VNRecognizeTextRequestRevision3
} else if #available(macOS 11, *) {
    REVISION = VNRecognizeTextRequestRevision2
}else{
    REVISION = VNRecognizeTextRequestRevision1
}

// 判断是否为使用空格分隔的语言
func isSpaceSeparatedLanguage(_ language: String) -> Bool {
    let spaceSeparatedLanguages = ["en", "fr", "de", "es", "it", "pt", "ru", "ar", "hi", "bn"]
    let characterSeparatedLanguages = ["zh", "ja", "ko", "th", "vi"]
    
    // 检查是否是字符分隔的语言（包括带变体的语言代码如 zh-Hans）
    for separatedLanguage in characterSeparatedLanguages {
        if language == separatedLanguage || language.hasPrefix(separatedLanguage + "-") {
            return false
        }
    }
    
    // 默认使用空格分隔（包括英语等西方语言）
    return true
}

/// 当前系统是否支持 Live Text（VisionKit 私有的 VKCImageAnalyzer SPI）。
/// 不支持时调用方应回退到 VNRecognizeTextRequest。
func isLiveTextAvailable() -> Bool {
    guard #available(macOS 13.0, *) else { return false }
    // 引用这个公开符号可以让 VisionKit 注册内部的 SPI 类
    guard VisionKit.ImageAnalyzer.isSupported else { return false }
    return NSClassFromString("VKCImageAnalyzer") != nil
        && NSClassFromString("VKCImageAnalyzerRequest") != nil
}

// MARK: - Live Text (VisionKit) 支持
//
// Live Text 由私有的 `VKCImageAnalyzer` SPI 类提供（ocrmac 的 Python 版本也是用它），
// SDK 里没有公开头文件，所以这里通过 Objective-C runtime 动态调用。

private let vkcMsgSend: UnsafeMutableRawPointer? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")

private typealias VKCAllocFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
private typealias VKCInitRequestFn = @convention(c) (AnyObject, Selector, AnyObject, UInt) -> Unmanaged<AnyObject>?
private typealias VKCProcessFn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject) -> Int32

/// 使用 Live Text 识别图片中的文字，并把结果写成与 Vision 路径相同结构的 JSON。
@available(macOS 13.0, *)
private func liveTextRecognize(image: NSImage, imageSize: CGSize, languages: [String], wordLevel: Bool, dst: String) -> Int32 {
    guard let msgSend = vkcMsgSend else {
        fputs("Error: unable to resolve objc_msgSend\n", stderr)
        return 1
    }
    guard let analyzerClass = NSClassFromString("VKCImageAnalyzer") as AnyObject?,
          let requestClass = NSClassFromString("VKCImageAnalyzerRequest") as AnyObject? else {
        fputs("Error: Live Text is not available on this system\n", stderr)
        return 1
    }

    let allocFn = unsafeBitCast(msgSend, to: VKCAllocFn.self)
    let initRequestFn = unsafeBitCast(msgSend, to: VKCInitRequestFn.self)
    let processFn = unsafeBitCast(msgSend, to: VKCProcessFn.self)

    let analyzer = allocFn(analyzerClass, NSSelectorFromString("alloc"))!.takeUnretainedValue()
    _ = initRequestFn(analyzer, NSSelectorFromString("init"), analyzer, 0)

    let allocatedRequest = allocFn(requestClass, NSSelectorFromString("alloc"))!.takeUnretainedValue()
    guard let request = initRequestFn(allocatedRequest, NSSelectorFromString("initWithImage:requestType:"), image, 1)?.takeRetainedValue() else {
        fputs("Error: failed to create a Live Text request\n", stderr)
        return 1
    }

    // 设置语言偏好（与 ocrmac 的 language_preference 一致）
    if !languages.isEmpty {
        _ = request.perform(NSSelectorFromString("setLocales:"), with: languages as NSArray)
    }

    let width = imageSize.width
    let height = imageSize.height
    let primaryLanguage = languages.first ?? "en"
    let useSpaceSeparator = isSpaceSeparatedLanguage(primaryLanguage)

    var finished = false
    var lines: [[String: Any]] = []
    var allText = ""
    var analysisError: String?

    let progressHandler: @convention(block) (Double) -> Void = { _ in }
    let completionHandler: @convention(block) (AnyObject?, AnyObject?) -> Void = { analysis, error in
        defer { finished = true }
        if let error = error {
            analysisError = "\(error)"
            return
        }
        guard let analysis = analysis else {
            analysisError = "no analysis result"
            return
        }

        func stringValue(_ object: NSObject) -> String {
            return (object.perform(NSSelectorFromString("string"))?.takeUnretainedValue() as? String) ?? ""
        }

        // VKQuad 的坐标是归一化的，且原点在左上角。
        func makeLine(_ object: NSObject, level: String) -> [String: Any] {
            let quad = object.value(forKey: "quad") as? NSObject
            func point(_ key: String) -> CGPoint {
                return (quad?.value(forKey: key) as? NSValue)?.pointValue ?? .zero
            }
            func pointValue(_ key: String) -> (Int, Int) {
                let p = point(key)
                return (Int(p.x * width), Int(p.y * height))
            }

            var rect = CGRect.zero
            if let value = quad?.value(forKey: "boundingBox") as? NSValue {
                rect = value.rectValue
            }

            let (x0, y0) = pointValue("topLeft")
            let (x1, y1) = pointValue("topRight")
            let (x2, y2) = pointValue("bottomRight")
            let (x3, y3) = pointValue("bottomLeft")

            var dict: [String: Any] = [:]
            dict["x0"] = x0
            dict["y0"] = y0
            dict["x1"] = x1
            dict["y1"] = y1
            dict["x2"] = x2
            dict["y2"] = y2
            dict["x3"] = x3
            dict["y3"] = y3
            dict["x"] = Int(rect.minX * width)
            dict["y"] = Int(rect.minY * height)
            dict["width"] = Int(rect.size.width * width)
            dict["height"] = Int(rect.size.height * height)
            dict["text"] = stringValue(object)
            dict["confidence"] = 1.0
            dict["level"] = level
            return dict
        }

        let lineObjects = analysis.perform(NSSelectorFromString("allLines"))?.takeUnretainedValue() as? NSArray ?? []
        var textParts: [String] = []
        for case let line as NSObject in lineObjects {
            textParts.append(stringValue(line))
            if wordLevel {
                let children = line.perform(NSSelectorFromString("children"))?.takeUnretainedValue() as? NSArray ?? []
                if children.count > 0 {
                    for case let child as NSObject in children {
                        lines.append(makeLine(child, level: useSpaceSeparator ? "word" : "character"))
                    }
                    continue
                }
            }
            lines.append(makeLine(line, level: "line"))
        }
        allText = textParts.joined(separator: "\n")
    }

    let progressObject = unsafeBitCast(progressHandler, to: AnyObject.self)
    let completionObject = unsafeBitCast(completionHandler, to: AnyObject.self)

    _ = processFn(analyzer, NSSelectorFromString("processRequest:progressHandler:completionHandler:"),
                  request as AnyObject, progressObject, completionObject)

    // Live Text 是异步的，这里跑 run loop 等待（与 ocrmac 跑 CFRunLoop 的做法一致）。
    let deadline = Date().addingTimeInterval(30)
    while !finished && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    withExtendedLifetime([progressHandler, completionHandler, request, analyzer]) {}

    if !finished {
        fputs("Error: Live Text analysis timed out\n", stderr)
        return 1
    }
    if let analysisError = analysisError {
        fputs("Error: Live Text analysis failed: \(analysisError)\n", stderr)
        return 1
    }

    var dict: [String: Any] = [:]
    dict["lines"] = lines
    dict["text"] = allText
    dict["word_level"] = wordLevel
    dict["language"] = primaryLanguage
    dict["segment_type"] = wordLevel ? (useSpaceSeparator ? "word" : "character") : "line"

    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let jsonString = String(data: data, encoding: .utf8) else {
        fputs("Error: failed to serialize Live Text result\n", stderr)
        return 1
    }
    do {
        try jsonString.write(to: URL(fileURLWithPath: dst), atomically: true, encoding: String.Encoding.utf8)
    } catch {
        fputs("Error: failed to write '\(dst)': \(error)\n", stderr)
        return 1
    }
    return 0
}

func main(args: [String]) -> Int32 {
    
    if CommandLine.arguments.count == 2 {
        if args[1] == "--langs" {
            let request = VNRecognizeTextRequest.init()
            request.revision = REVISION
            request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
            var langs:[String] = []
            if #available(macOS 12, *) {
                langs = try! request.supportedRecognitionLanguages()
            } else {
                langs = try! VNRecognizeTextRequest.supportedRecognitionLanguages(for: request.recognitionLevel, revision:request.revision)
            }
            for lang in langs {
                print(lang)
            }
        }
        return 0
    } else if CommandLine.arguments.count >= 3 && args[1] == "--langs" {
        // 支持指定识别级别
        let levelArg = args[2].lowercased()

        // Live Text 支持的语言来自 VisionKit 的 ImageAnalyzer
        if levelArg == "livetext" {
            if #available(macOS 13.0, *) {
                for lang in VisionKit.ImageAnalyzer.supportedTextRecognitionLanguages {
                    print(lang)
                }
            } else {
                fputs("Error: Live Text requires macOS 13.0 or later\n", stderr)
                return 1
            }
            return 0
        }

        var recognitionLevel: VNRequestTextRecognitionLevel
        
        if levelArg == "fast" {
            recognitionLevel = .fast
        } else if levelArg == "accurate" {
            recognitionLevel = .accurate
        } else {
            // 如果参数无效，默认使用 accurate
            recognitionLevel = .accurate
        }
        
        let request = VNRecognizeTextRequest.init()
        request.revision = REVISION
        request.recognitionLevel = recognitionLevel
        var langs:[String] = []
        if #available(macOS 12, *) {
            langs = try! request.supportedRecognitionLanguages()
        } else {
            langs = try! VNRecognizeTextRequest.supportedRecognitionLanguages(for: request.recognitionLevel, revision:request.revision)
        }
        for lang in langs {
            print(lang)
        }
        return 0
    } else if CommandLine.arguments.count >= 6 {
        let (language, fastmode, languageCorrection, wordLevel, src, dst) =
            (args[1], args[2], args[3], args.count >= 7 ? args[4] : "false",
             args.count >= 7 ? args[5] : args[4], args.count >= 7 ? args[6] : args[5])
        
        let substrings = language.split(separator: ",")
        var languages:[String] = []
        for substring in substrings {
            languages.append(String(substring))
        }
        
        switch fastmode.lowercased() {
        case "true", "fast":
            MODE = VNRequestTextRecognitionLevel.fast
        case "livetext":
            // Live Text 优先；系统不支持时回退到 accurate
            if isLiveTextAvailable() {
                USE_LIVETEXT = true
            } else {
                MODE = VNRequestTextRecognitionLevel.accurate
                fputs("Warning: Live Text is not available on this system, falling back to accurate mode\n", stderr)
            }
        default:
            // "false" 或 "accurate"
            MODE = VNRequestTextRecognitionLevel.accurate
        }
        
        if languageCorrection == "true" {
            USE_LANG_CORRECTION = true
        }else{
            USE_LANG_CORRECTION = false
        }
        
        // 新增：设置单词级别识别
        if wordLevel == "true" {
            WORD_LEVEL = true
        }else{
            WORD_LEVEL = false
        }

        guard let img = NSImage(byReferencingFile: src) else {
            fputs("Error: failed to load image '\(src)'\n", stderr)
            return 1
        }
        guard let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("Error: failed to convert NSImage to CGImage for '\(src)'\n", stderr)
            return 1
        }

        // Live Text 走 VisionKit 的 VKCImageAnalyzer，输出结构与 Vision 路径保持一致
        if USE_LIVETEXT {
            if #available(macOS 13.0, *) {
                return liveTextRecognize(
                    image: img,
                    imageSize: CGSize(width: imgRef.width, height: imgRef.height),
                    languages: languages,
                    wordLevel: WORD_LEVEL,
                    dst: dst
                )
            } else {
                fputs("Error: Live Text requires macOS 13.0 or later\n", stderr)
                return 1
            }
        }

        let request = VNRecognizeTextRequest { (request, error) in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            var dict:[String:Any] = [:]
            var lines:[Any] = []
            var allText = ""
            var index = 0
            
            // 获取主要语言用于确定分隔方式
            let primaryLanguage = languages.first ?? "en"
            let useSpaceSeparator = isSpaceSeparatedLanguage(primaryLanguage)
            
            for observation in observations {
                // Find the top observation.
                let candidate = observation.topCandidates(1).first
                let string = candidate?.string ?? ""
                let confidence = candidate?.confidence ?? 0.0
                
                if WORD_LEVEL {
                    // 单词级别：根据语言选择分隔符
                    let segments: [String]
                    if useSpaceSeparator {
                        // 空格分隔语言：按单词分割
                        segments = string.split(separator: " ").map(String.init)
                    } else {
                        // 字符分隔语言：按字符分割
                        segments = string.map(String.init)
                    }
                    
                    var currentPosition = string.startIndex
                    
                    for (segmentIndex, segment) in segments.enumerated() {
                        // 计算段落在原始字符串中的范围
                        let segmentRangeStart = currentPosition
                        let segmentRangeEnd = string.index(segmentRangeStart, offsetBy: segment.count, limitedBy: string.endIndex) ?? string.endIndex
                        let segmentRange = segmentRangeStart..<segmentRangeEnd
                        
                        // 获取段落的边界框
                        if let segmentBoxObservation = try? candidate?.boundingBox(for: segmentRange) {
                            var segmentDict:[String:Any] = [:]
                            
                            segmentDict["x0"] = Int((segmentBoxObservation.topLeft.x) * CGFloat(imgRef.width))
                            segmentDict["y0"] = Int(CGFloat(imgRef.height) - (segmentBoxObservation.topLeft.y) * CGFloat(imgRef.height))
                            segmentDict["x1"] = Int((segmentBoxObservation.topRight.x) * CGFloat(imgRef.width))
                            segmentDict["y1"] = Int(CGFloat(imgRef.height) - (segmentBoxObservation.topRight.y) * CGFloat(imgRef.height))
                            segmentDict["x2"] = Int((segmentBoxObservation.bottomRight.x) * CGFloat(imgRef.width))
                            segmentDict["y2"] = Int(CGFloat(imgRef.height) - (segmentBoxObservation.bottomRight.y) * CGFloat(imgRef.height))
                            segmentDict["x3"] = Int((segmentBoxObservation.bottomLeft.x) * CGFloat(imgRef.width))
                            segmentDict["y3"] = Int(CGFloat(imgRef.height) - (segmentBoxObservation.bottomLeft.y) * CGFloat(imgRef.height))
                            
                            // 获取归一化的边界框并转换为图像坐标
                            let segmentBoundingBox = segmentBoxObservation.boundingBox
                            let rect = VNImageRectForNormalizedRect(segmentBoundingBox,
                                                                    Int(imgRef.width),
                                                                    Int(imgRef.height))
                            
                            segmentDict["text"] = segment
                            segmentDict["confidence"] = confidence
                            segmentDict["x"] = Int(rect.minX)
                            segmentDict["width"] = Int(rect.size.width)
                            segmentDict["y"] = Int(CGFloat(imgRef.height) - rect.minY - rect.size.height)
                            segmentDict["height"] = Int(rect.size.height)
                            segmentDict["level"] = useSpaceSeparator ? "word" : "character" // 标记级别
                            
                            lines.append(segmentDict)
                        }
                        
                        // 更新位置到下一个段落的起始位置
                        if segmentIndex < segments.count - 1 {
                            // 移动到当前段落末尾
                            currentPosition = segmentRangeEnd
                            // 对于空格分隔语言，跳过空格
                            if useSpaceSeparator && currentPosition < string.endIndex && string[currentPosition] == " " {
                                currentPosition = string.index(after: currentPosition)
                            }
                        }
                        
                        // 安全检查：防止索引越界
                        if currentPosition >= string.endIndex {
                            break
                        }
                    }
                } else {
                    // 行级别：原有逻辑
                    var line:[String:Any] = [:]
                    let stringRange = string.startIndex..<string.endIndex
                    let boxObservation = try? candidate?.boundingBox(for: stringRange)
                    
                    line["x0"] = Int((boxObservation?.topLeft.x ?? 0) * CGFloat(imgRef.width))
                    line["y0"] = Int(CGFloat(imgRef.height) - (boxObservation?.topLeft.y ?? 0) * CGFloat(imgRef.height))
                    line["x1"] = Int((boxObservation?.topRight.x ?? 0) * CGFloat(imgRef.width))
                    line["y1"] = Int(CGFloat(imgRef.height) - (boxObservation?.topRight.y ?? 0) * CGFloat(imgRef.height))
                    line["x2"] = Int((boxObservation?.bottomRight.x ?? 0) * CGFloat(imgRef.width))
                    line["y2"] = Int(CGFloat(imgRef.height) - (boxObservation?.bottomRight.y ?? 0) * CGFloat(imgRef.height))
                    line["x3"] = Int((boxObservation?.bottomLeft.x ?? 0) * CGFloat(imgRef.width))
                    line["y3"] = Int(CGFloat(imgRef.height) - (boxObservation?.bottomLeft.y ?? 0) * CGFloat(imgRef.height))
                    
                    let boundingBox = boxObservation?.boundingBox ?? .zero
                    let rect = VNImageRectForNormalizedRect(boundingBox,
                                                            Int(imgRef.width),
                                                            Int(imgRef.height))
                    
                    line["text"] = string
                    line["confidence"] = confidence
                    line["x"] = Int(rect.minX)
                    line["width"] = Int(rect.size.width)
                    line["y"] = Int(CGFloat(imgRef.height) - rect.minY - rect.size.height)
                    line["height"] = Int(rect.size.height)
                    line["level"] = "line" // 标记为行级别
                    
                    lines.append(line)
                }
                
                allText = allText + string
                index = index + 1
                if index != observations.count {
                   allText = allText + "\n"
                }
            }
            
            dict["lines"] = lines
            dict["text"] = allText
            dict["word_level"] = WORD_LEVEL // 在输出中标记是否启用了单词级别
            dict["language"] = primaryLanguage // 添加语言信息
            dict["segment_type"] = WORD_LEVEL ? (useSpaceSeparator ? "word" : "character") : "line" // 添加分段类型
            
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
            let jsonString = String(data: data!,
                                    encoding: .utf8) ?? "[]"
            try? jsonString.write(to: URL(fileURLWithPath: dst), atomically: true, encoding: String.Encoding.utf8)
        }
        
        request.recognitionLevel = MODE
        request.usesLanguageCorrection = USE_LANG_CORRECTION
        request.revision = REVISION
        request.recognitionLanguages = languages
        
        try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])
        return 0
    }else{
        print("""
              usage:
                language mode languageCorrection [wordLevel] image_path output_path
                mode: fast/true (快速), accurate/false (精确, 默认), livetext (Live Text, macOS 13+, 不支持时回退到 accurate)
                --langs [fast|accurate|livetext]: list suppported languages for specified recognition level
              
              examples:
                # 行级别识别
                macOCR en false true false ./image.jpg out.json
                
                # 单词级别识别（英语）
                macOCR en false true true ./image.jpg out.json
                
                # 字符级别识别（中文）
                macOCR zh-Hans false true true ./image.jpg out.json
                
                # Live Text 识别（macOS 13+，不支持时自动回退到 accurate）
                macOCR en livetext true false ./image.jpg out.json
                
                # 向后兼容的用法（行级别）
                macOCR en false true ./image.jpg out.json
                
                # 列出支持的语言（accurate 级别，默认）
                macOCR --langs
                
                # 列出支持的语言（fast 级别）
                macOCR --langs fast
                
                # 列出支持的语言（livetext 级别，macOS 13+）
                macOCR --langs livetext
              """)
        return 1
    }
}

exit(main(args: CommandLine.arguments))

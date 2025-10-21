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
var WORD_LEVEL = false // 新增：是否启用单词级别识别
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
    
    if characterSeparatedLanguages.contains(language) {
        return false
    }
    // 默认使用空格分隔（包括英语等西方语言）
    return true
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
    }else if CommandLine.arguments.count >= 6 {
        let (language, fastmode, languageCorrection, wordLevel, src, dst) =
            (args[1], args[2], args[3], args.count >= 7 ? args[4] : "false",
             args.count >= 7 ? args[5] : args[4], args.count >= 7 ? args[6] : args[5])
        
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
                language fastmode languageCorrection [wordLevel] image_path output_path
                --langs: list suppported languages
              
              examples:
                # 行级别识别
                macOCR en false true false ./image.jpg out.json
                
                # 单词级别识别（英语）
                macOCR en false true true ./image.jpg out.json
                
                # 字符级别识别（中文）
                macOCR zh-Hans false true true ./image.jpg out.json
                
                # 向后兼容的用法（行级别）
                macOCR en false true ./image.jpg out.json
              """)
        return 1
    }
}

exit(main(args: CommandLine.arguments))

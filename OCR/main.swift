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
            
            for observation in observations {
                // Find the top observation.
                let candidate = observation.topCandidates(1).first
                let string = candidate?.string ?? ""
                let confidence = candidate?.confidence ?? 0.0
                
                if WORD_LEVEL {
                    // 单词级别：按空格分割文本，获取每个单词的边界框
                    let words = string.split(separator: " ")
                    var currentPosition = string.startIndex
                    
                    for (wordIndex, word) in words.enumerated() {
                        let wordString = String(word)
                        
                        // 计算单词在原始字符串中的范围
                        let wordRangeStart = currentPosition
                        let wordRangeEnd = string.index(wordRangeStart, offsetBy: word.count, limitedBy: string.endIndex) ?? string.endIndex
                        let wordRange = wordRangeStart..<wordRangeEnd
                        
                        // 获取单词的边界框
                        if let wordBoxObservation = try? candidate?.boundingBox(for: wordRange) {
                            var wordDict:[String:Any] = [:]
                            
                            wordDict["x0"] = Int((wordBoxObservation.topLeft.x) * CGFloat(imgRef.width))
                            wordDict["y0"] = Int(CGFloat(imgRef.height) - (wordBoxObservation.topLeft.y) * CGFloat(imgRef.height))
                            wordDict["x1"] = Int((wordBoxObservation.topRight.x) * CGFloat(imgRef.width))
                            wordDict["y1"] = Int(CGFloat(imgRef.height) - (wordBoxObservation.topRight.y) * CGFloat(imgRef.height))
                            wordDict["x2"] = Int((wordBoxObservation.bottomRight.x) * CGFloat(imgRef.width))
                            wordDict["y2"] = Int(CGFloat(imgRef.height) - (wordBoxObservation.bottomRight.y) * CGFloat(imgRef.height))
                            wordDict["x3"] = Int((wordBoxObservation.bottomLeft.x) * CGFloat(imgRef.width))
                            wordDict["y3"] = Int(CGFloat(imgRef.height) - (wordBoxObservation.bottomLeft.y) * CGFloat(imgRef.height))
                            
                            // 获取归一化的边界框并转换为图像坐标
                            let wordBoundingBox = wordBoxObservation.boundingBox
                            let rect = VNImageRectForNormalizedRect(wordBoundingBox,
                                                                    Int(imgRef.width),
                                                                    Int(imgRef.height))
                            
                            wordDict["text"] = wordString
                            wordDict["confidence"] = confidence
                            wordDict["x"] = Int(rect.minX)
                            wordDict["width"] = Int(rect.size.width)
                            wordDict["y"] = Int(CGFloat(imgRef.height) - rect.minY - rect.size.height)
                            wordDict["height"] = Int(rect.size.height)
                            wordDict["level"] = "word" // 标记为单词级别
                            
                            lines.append(wordDict)
                        }
                        
                        // 更新位置到下一个单词的起始位置（跳过空格）
                        if wordIndex < words.count - 1 {
                            // 移动到当前单词末尾
                            currentPosition = wordRangeEnd
                            // 跳过空格（如果有的话）
                            if currentPosition < string.endIndex && string[currentPosition] == " " {
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
                
                # 单词级别识别  
                macOCR en false true true ./image.jpg out.json
                
                # 向后兼容的用法（行级别）
                macOCR en false true ./image.jpg out.json
              """)
        return 1
    }
}

exit(main(args: CommandLine.arguments))

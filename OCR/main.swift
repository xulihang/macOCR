//
//  main.swift
//  OCR
//
//  Created by xulihang on 2023/1/1.
//  Optimized: script-aware word segmentation for multilingual OCR.
//

import Vision
import Cocoa
import Foundation
import NaturalLanguage

// MARK: - Global settings

var MODE = VNRequestTextRecognitionLevel.accurate // or .fast
var USE_LANG_CORRECTION = false
var WORD_LEVEL = false          // 是否启用单词/字符级别识别
var CJK_BY_WORD = false         // CJK 是否按词组切分（false = 逐字）
var MERGE_LETTER_DIGIT = false  // 字母与数字是否合并为一段（如 "abc123"）
var REVISION: Int

if #available(macOS 13, *) {
    REVISION = VNRecognizeTextRequestRevision3
} else if #available(macOS 11, *) {
    REVISION = VNRecognizeTextRequestRevision2
} else {
    REVISION = VNRecognizeTextRequestRevision1
}

// MARK: - Script detection (regex based, since Unicode.Scalar.Properties has no `script`)

/// CJK 判断：汉字、平假名、片假名、韩文
func isCJK(_ s: String) -> Bool {
    return s.range(of: "\\p{Han}|\\p{Hiragana}|\\p{Katakana}|\\p{Hangul}",
                   options: .regularExpression) != nil
}

func scriptName(for text: String) -> String {
    guard let firstChar = text.first else { return "unknown" }
    let s = String(firstChar)

    if s.range(of: "\\p{Han}", options: .regularExpression) != nil { return "han" }
    if s.range(of: "\\p{Hiragana}", options: .regularExpression) != nil { return "hiragana" }
    if s.range(of: "\\p{Katakana}", options: .regularExpression) != nil { return "katakana" }
    if s.range(of: "\\p{Hangul}", options: .regularExpression) != nil { return "hangul" }
    if s.range(of: "\\p{Arabic}", options: .regularExpression) != nil { return "arabic" }
    if s.range(of: "\\p{Hebrew}", options: .regularExpression) != nil { return "hebrew" }
    if s.range(of: "\\p{Latin}", options: .regularExpression) != nil { return "latin" }
    if s.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil { return "cyrillic" }
    if s.range(of: "\\p{Greek}", options: .regularExpression) != nil { return "greek" }
    if s.range(of: "\\p{Thai}", options: .regularExpression) != nil { return "thai" }
    if s.range(of: "\\p{Devanagari}", options: .regularExpression) != nil { return "devanagari" }
    return "other"
}

// MARK: - Script-aware segmentation

enum ScriptClass {
    case cjk          // 汉字、平假名、片假名、韩文
    case letter       // 拉丁、西里尔、希腊、阿拉伯、希伯来等字母
    case digit        // 数字
    case other        // 标点、符号、空白
}

/// 用 CharacterSet 做标点/符号判断，用正则做 CJK 判断，
/// 避免依赖不存在的 Unicode.Scalar.Properties.script。
func classify(_ scalar: Unicode.Scalar) -> ScriptClass {
    // 空白
    if scalar.properties.isWhitespace { return .other }

    // 标点 / 符号 / 控制字符
    let nonTextSet = CharacterSet.punctuationCharacters
        .union(.symbols)
        .union(.controlCharacters)
    if nonTextSet.contains(scalar) { return .other }

    // 数字
    if scalar.properties.numericType != nil { return .digit }

    // CJK（正则判断）
    let s = String(scalar)
    if isCJK(s) { return .cjk }

    // 其余字母类
    if scalar.properties.isAlphabetic { return .letter }
    return .other
}

struct Segment {
    let text: String
    let range: Range<String.Index>
}

/// 逐字符按 Unicode Script 分段：
/// - CJK 每个字符单独成段（可选按词组，见 CJK_BY_WORD）
/// - letter / digit 连续累积成段
/// - 空白、标点作为分隔符丢弃
func segmentByScript(_ s: String,
                     mergeLetterDigit: Bool,
                     cjkByWord: Bool) -> [Segment] {
    var raw: [Segment] = []
    var segStart: String.Index? = nil
    var segClass: ScriptClass = .other

    func flush(_ end: String.Index) {
        if let start = segStart, start < end {
            raw.append(Segment(text: String(s[start..<end]), range: start..<end))
        }
        segStart = nil
    }

    var i = s.startIndex
    while i < s.endIndex {
        let next = s.index(after: i)
        let scalar = s[i].unicodeScalars.first!
        let cls = classify(scalar)

        if cls == .other {
            flush(i)
            i = next
            continue
        }

        if cls == .cjk {
            flush(i)
            raw.append(Segment(text: String(s[i..<next]), range: i..<next))
            i = next
            continue
        }

        if let start = segStart {
            let sameKind: Bool
            if mergeLetterDigit {
                sameKind = (segClass == .letter || segClass == .digit)
                        && (cls == .letter || cls == .digit)
            } else {
                sameKind = (segClass == cls)
            }
            if sameKind {
                i = next
                continue
            } else {
                flush(i)
                segStart = i
                segClass = cls
                i = next
                continue
            }
        } else {
            segStart = i
            segClass = cls
            i = next
            continue
        }
    }
    flush(s.endIndex)

    if !cjkByWord {
        return raw
    }

    return regroupCJKByWord(raw, in: s)
}

/// 把 raw 中连续的 CJK 单字段落合并成一个区间，再用 NLTokenizer 按词切
func regroupCJKByWord(_ raw: [Segment], in s: String) -> [Segment] {
    var result: [Segment] = []
    var i = 0
    while i < raw.count {
        let seg = raw[i]
        let segIsCJK = isCJK(seg.text)

        if !segIsCJK {
            result.append(seg)
            i += 1
            continue
        }

        // 收集连续 CJK 段
        var j = i
        let lower = seg.range.lowerBound
        var upper = seg.range.upperBound
        while j + 1 < raw.count {
            let nxt = raw[j + 1]
            if !isCJK(nxt.text) { break }
            if nxt.range.lowerBound != upper { break }
            upper = nxt.range.upperBound
            j += 1
        }

        let block = String(s[lower..<upper])
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = block
        var produced = false
        tokenizer.enumerateTokens(in: block.startIndex..<block.endIndex) { r, _ in
            let lo = block.index(lower,
                                 offsetBy: block.distance(from: block.startIndex,
                                                          to: r.lowerBound))
            let hi = block.index(lower,
                                 offsetBy: block.distance(from: block.startIndex,
                                                          to: r.upperBound))
            result.append(Segment(text: String(s[lo..<hi]), range: lo..<hi))
            produced = true
            return true
        }
        if !produced {
            result.append(Segment(text: block, range: lower..<upper))
        }
        i = j + 1
    }
    return result
}

// MARK: - Geometry helpers

struct CornerPoints {
    let x0, y0: Int   // topLeft
    let x1, y1: Int   // topRight
    let x2, y2: Int   // bottomRight
    let x3, y3: Int   // bottomLeft
}

func corners(_ obs: VNRectangleObservation,
             imageWidth: Int, imageHeight: Int) -> CornerPoints {
    func px(_ p: CGPoint) -> (Int, Int) {
        (Int(p.x * CGFloat(imageWidth)),
         Int(CGFloat(imageHeight) - p.y * CGFloat(imageHeight)))
    }
    let (x0, y0) = px(obs.topLeft)
    let (x1, y1) = px(obs.topRight)
    let (x2, y2) = px(obs.bottomRight)
    let (x3, y3) = px(obs.bottomLeft)
    return CornerPoints(x0: x0, y0: y0, x1: x1, y1: y1,
                        x2: x2, y2: y2, x3: x3, y3: y3)
}

func aabb(_ c: CornerPoints) -> (x: Int, y: Int, w: Int, h: Int) {
    let minX = min(c.x0, c.x1, c.x2, c.x3)
    let maxX = max(c.x0, c.x1, c.x2, c.x3)
    let minY = min(c.y0, c.y1, c.y2, c.y3)
    let maxY = max(c.y0, c.y1, c.y2, c.y3)
    return (minX, minY, maxX - minX, maxY - minY)
}

func levelName(for text: String) -> String {
    if text.count == 1, isCJK(text) {
        return "character"
    }
    return "word"
}

// MARK: - Usage

func printUsage() {
    print("""
    usage:
      language fastmode languageCorrection [wordLevel] [cjkByWord] [mergeLetterDigit] image_path output_path
      --langs [fast|accurate]: list supported languages for specified recognition level

    examples:
      # 行级别识别
      macOCR en false true ./image.jpg out.json

      # 单词级别识别（脚本感知，CJK 逐字）
      macOCR en,zh-Hans false true true ./image.jpg out.json

      # 单词级别识别（CJK 按词组）
      macOCR en,zh-Hans false true true true ./image.jpg out.json

      # 单词级别识别（字母数字合并）
      macOCR en false true true false true ./image.jpg out.json

      # 列出支持的语言（accurate 级别，默认）
      macOCR --langs

      # 列出支持的语言（fast 级别）
      macOCR --langs fast

    notes:
      - wordLevel:      是否输出单词/字符级别结果（默认 false）
      - cjkByWord:      CJK 是否按词组切分（默认 false，即逐字）
      - mergeLetterDigit: 字母与数字是否合并为一段，如 "abc123"（默认 false）
    """)
}

// MARK: - Main

func main(args: [String]) -> Int32 {

    // ---- --langs ----
    if CommandLine.arguments.count == 2, args[1] == "--langs" {
        let request = VNRecognizeTextRequest.init()
        request.revision = REVISION
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        var langs: [String] = []
        if #available(macOS 12, *) {
            langs = (try? request.supportedRecognitionLanguages()) ?? []
        } else {
            langs = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: request.recognitionLevel, revision: request.revision)) ?? []
        }
        for lang in langs { print(lang) }
        return 0
    }

    if CommandLine.arguments.count >= 3, args[1] == "--langs" {
        let levelArg = args[2].lowercased()
        let recognitionLevel: VNRequestTextRecognitionLevel =
            (levelArg == "fast") ? .fast : .accurate

        let request = VNRecognizeTextRequest.init()
        request.revision = REVISION
        request.recognitionLevel = recognitionLevel
        var langs: [String] = []
        if #available(macOS 12, *) {
            langs = (try? request.supportedRecognitionLanguages()) ?? []
        } else {
            langs = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: request.recognitionLevel, revision: request.revision)) ?? []
        }
        for lang in langs { print(lang) }
        return 0
    }

    // ---- OCR 主流程 ----
    guard CommandLine.arguments.count >= 6 else {
        printUsage()
        return 1
    }

    let language = args[1]
    let fastmode = args[2]
    let languageCorrection = args[3]

    let remaining = Array(args[4...])
    guard remaining.count >= 2 else {
        printUsage()
        return 1
    }

    let optionalFlags = Array(remaining.dropLast(2))
    let src = remaining[remaining.count - 2]
    let dst = remaining[remaining.count - 1]

    var wordLevelStr = "false"
    var cjkByWordStr = "false"
    var mergeLetterDigitStr = "false"
    if optionalFlags.count >= 1 { wordLevelStr = optionalFlags[0] }
    if optionalFlags.count >= 2 { cjkByWordStr = optionalFlags[1] }
    if optionalFlags.count >= 3 { mergeLetterDigitStr = optionalFlags[2] }

    let substrings = language.split(separator: ",")
    var languages: [String] = []
    for substring in substrings {
        languages.append(String(substring))
    }

    MODE = (fastmode == "true") ? .fast : .accurate
    USE_LANG_CORRECTION = (languageCorrection == "true")
    WORD_LEVEL = (wordLevelStr == "true")
    CJK_BY_WORD = (cjkByWordStr == "true")
    MERGE_LETTER_DIGIT = (mergeLetterDigitStr == "true")

    guard let img = NSImage(byReferencingFile: src) else {
        fputs("Error: failed to load image '\(src)'\n", stderr)
        return 1
    }
    guard let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: failed to convert NSImage to CGImage for '\(src)'\n", stderr)
        return 1
    }

    let imgW = Int(imgRef.width)
    let imgH = Int(imgRef.height)

    let request = VNRecognizeTextRequest { (request, error) in
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        var dict: [String: Any] = [:]
        var lines: [Any] = []
        var allText = ""
        var index = 0

        for observation in observations {
            let candidate = observation.topCandidates(1).first
            let string = candidate?.string ?? ""
            let confidence = candidate?.confidence ?? 0.0

            if WORD_LEVEL {
                // ---- 脚本感知切词 ----
                let segments = segmentByScript(string,
                                               mergeLetterDigit: MERGE_LETTER_DIGIT,
                                               cjkByWord: CJK_BY_WORD)

                for seg in segments {
                    guard let boxObs = try? candidate?.boundingBox(for: seg.range) else {
                        continue
                    }
                    var d: [String: Any] = [:]
                    let c = corners(boxObs, imageWidth: imgW, imageHeight: imgH)
                    d["x0"] = c.x0; d["y0"] = c.y0
                    d["x1"] = c.x1; d["y1"] = c.y1
                    d["x2"] = c.x2; d["y2"] = c.y2
                    d["x3"] = c.x3; d["y3"] = c.y3

                    let r = aabb(c)
                    d["x"] = r.x
                    d["y"] = r.y
                    d["width"] = r.w
                    d["height"] = r.h

                    d["text"] = seg.text
                    d["confidence"] = confidence
                    d["level"] = levelName(for: seg.text)
                    d["script"] = scriptName(for: seg.text)

                    lines.append(d)
                }
            } else {
                // ---- 行级 ----
                var line: [String: Any] = [:]
                let stringRange = string.startIndex..<string.endIndex
                let boxObservation = try? candidate?.boundingBox(for: stringRange)

                if let bo = boxObservation {
                    let c = corners(bo, imageWidth: imgW, imageHeight: imgH)
                    line["x0"] = c.x0; line["y0"] = c.y0
                    line["x1"] = c.x1; line["y1"] = c.y1
                    line["x2"] = c.x2; line["y2"] = c.y2
                    line["x3"] = c.x3; line["y3"] = c.y3

                    let r = aabb(c)
                    line["x"] = r.x
                    line["y"] = r.y
                    line["width"] = r.w
                    line["height"] = r.h
                } else {
                    line["x0"] = 0; line["y0"] = 0
                    line["x1"] = 0; line["y1"] = 0
                    line["x2"] = 0; line["y2"] = 0
                    line["x3"] = 0; line["y3"] = 0
                    line["x"] = 0; line["y"] = 0
                    line["width"] = 0; line["height"] = 0
                }

                line["text"] = string
                line["confidence"] = confidence
                line["level"] = "line"
                line["script"] = scriptName(for: string)

                lines.append(line)
            }

            allText += string
            index += 1
            if index != observations.count {
                allText += "\n"
            }
        }

        dict["lines"] = lines
        dict["text"] = allText
        dict["word_level"] = WORD_LEVEL
        dict["cjk_by_word"] = CJK_BY_WORD
        dict["merge_letter_digit"] = MERGE_LETTER_DIGIT
        dict["language"] = languages
        dict["segment_type"] = WORD_LEVEL ? "script_aware" : "line"

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            try? jsonString.write(to: URL(fileURLWithPath: dst),
                                  atomically: true,
                                  encoding: .utf8)
        }
    }

    request.recognitionLevel = MODE
    request.usesLanguageCorrection = USE_LANG_CORRECTION
    request.revision = REVISION
    request.recognitionLanguages = languages

    try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])
    return 0
}

exit(main(args: CommandLine.arguments))

import Vision
import Cocoa
import PDFKit

func round3(_ v: Double) -> NSDecimalNumber {
    // Round using Decimal to 3 decimal places (base-10)
    var dec = Decimal(v)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &dec, 3, .plain)

    // Get a base-10 string for the rounded value
    var s = NSDecimalNumber(decimal: rounded).stringValue

    // Ensure exactly 3 fractional digits (pad or truncate if necessary)
    if let dotIndex = s.firstIndex(of: ".") {
        let frac = s[s.index(after: dotIndex)...]
        if frac.count < 3 {
            s += String(repeating: "0", count: 3 - frac.count)
        } else if frac.count > 3 {
            // Defensive: should not happen because we rounded to 3, but if it does, truncate to 3.
            let intPart = s[..<dotIndex]
            let fracPrefix = frac.prefix(3)
            s = String(intPart) + "." + String(fracPrefix)
        }
    } else {
        // No decimal point -> add .000
        s += ".000"
    }

    return NSDecimalNumber(string: s)
}

func round3(_ v: CGFloat) -> NSDecimalNumber {
    return round3(Double(v))
}

@available(macOS 15.0, *)
func performOCR(cgImage: CGImage, languages: [String]) -> [String: Any]? {
    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
    } catch {
        fputs("OCR execution failed for image: \(error.localizedDescription)\n", stderr)
        return nil
    }

    guard let results = request.results else {
        fputs("No text results for image.\n", stderr)
        return nil
    }

    var observations: [[String: Any]] = []

    for observation in results {
        guard let candidate = observation.topCandidates(1).first else { continue }

        let range = candidate.string.startIndex..<candidate.string.endIndex
        let box = (try? candidate.boundingBox(for: range)?.boundingBox) ?? observation.boundingBox

        let absBox = VNImageRectForNormalizedRect(box, Int(imageWidth), Int(imageHeight))
        let flippedY = imageHeight - absBox.origin.y - absBox.size.height

        observations.append([
            "text": candidate.string,
            "bbox": [
                "x": round3(absBox.origin.x),
                "y": round3(flippedY),
                "width": round3(absBox.size.width),
                "height": round3(absBox.size.height)
            ]
        ])
    }

    return [
        "width": Int(imageWidth),
        "height": Int(imageHeight),
        "observations": observations
    ]
}

@available(macOS 15.0, *)
func performOCR(on imagePath: String, languages: [String]) -> [String: Any]? {
    guard let img = NSImage(byReferencingFile: imagePath),
          let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: failed to load or convert image '\(imagePath)'\n", stderr)
        return nil
    }

    return performOCR(cgImage: imgRef, languages: languages)
}

@available(macOS 15.0, *)
func writeJSONObjectOrdered(_ object: [String: Any], to finalOutputPath: String) throws {
    // Ensure deterministic order: use localizedStandardCompare for filenames and numeric order for numeric keys
    let keys = object.keys.sorted { a, b in
        // numeric compare if both are pure integers
        if let ai = Int(a), let bi = Int(b) { return ai < bi }
        // otherwise use localizedStandardCompare to get natural (numeric-aware) ordering ("22.png" before "111.png")
        return a.localizedStandardCompare(b) == .orderedAscending
    }

    let ordered = NSMutableDictionary()
    for k in keys {
        ordered[k] = object[k]
    }

    let jsonData = try JSONSerialization.data(withJSONObject: ordered, options: [.prettyPrinted])
    try jsonData.write(to: URL(fileURLWithPath: finalOutputPath))
}

@available(macOS 15.0, *)
func main(args: [String]) -> Int32 {
    if CommandLine.arguments.count < 3 {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        let langs = (try? request.supportedRecognitionLanguages()) ?? []

        if let data = try? JSONSerialization.data(withJSONObject: langs, options: []),
           let langsJson = String(data: data, encoding: .utf8) {
            print("supported_languages:\(langsJson)")
        }

        print("""
        usage:
          macOCR languages image_or_directory_path [output_directory_or_filename]

        examples:
          macOCR en ./image.jpg
          macOCR en ./images/ ./ocr_output/
          macOCR en ./document.pdf ./my_pdf_pages.json

        Notes:
        - If output_directory_or_filename ends with .json it will be used as the exact output file name.
        - If a directory is given for batch processing and no output is provided, a 'batch_output.json' file is written into the input directory.
        """)
        return 1
    }

    let languageArg = args[1]
    let inputPath = args[2]
    let outputPath = args.count > 3 ? args[3] : nil
    var pageRange: ClosedRange<Int>? = nil
    if args.count > 4 {
        let parts = args[4].split(separator: "-").compactMap { Int($0) }
        if parts.count == 2, parts[0] > 0, parts[1] >= parts[0] {
            pageRange = parts[0]...parts[1]
        }
    }
    let languages = languageArg.split(separator: ",").map { String($0) }

    var isDir: ObjCBool = false
    let fileManager = FileManager.default
    let inputURL = URL(fileURLWithPath: inputPath)

    if fileManager.fileExists(atPath: inputPath, isDirectory: &isDir), isDir.boolValue {
        // Directory (batch image processing)
        guard let files = try? fileManager.contentsOfDirectory(atPath: inputPath) else {
            fputs("Error reading directory: \(inputPath)\n", stderr)
            return 1
        }

        // filter image files and sort with natural/localized ordering so "22.png" comes before "111.png"
        let imageFiles = files.filter {
            let lc = $0.lowercased()
            return lc.hasSuffix(".jpg") || lc.hasSuffix(".jpeg") || lc.hasSuffix(".png")
        }.sorted { a, b in
            a.localizedStandardCompare(b) == .orderedAscending
        }

        var batchOutput: [String: Any] = [:]

        for file in imageFiles {
            let fullPath = (inputPath as NSString).appendingPathComponent(file)
            if let ocrResult = performOCR(on: fullPath, languages: languages) {
                batchOutput[file] = ocrResult
            }
        }

        // determine final output path: if provided and ends with .json, use as filename; otherwise treat as directory
        let finalOutputPath: String
        if let out = outputPath {
            if out.lowercased().hasSuffix(".json") {
                finalOutputPath = out
            } else {
                finalOutputPath = (out as NSString).appendingPathComponent("batch_output.json")
            }
        } else {
            finalOutputPath = (inputURL.path as NSString).appendingPathComponent("batch_output.json")
        }

        do {
            try writeJSONObjectOrdered(batchOutput, to: finalOutputPath)
            print("✅ Batch OCR data written to \(finalOutputPath)")
        } catch {
            fputs("Error writing batch JSON: \(error.localizedDescription)\n", stderr)
            return 1
        }
    } else {
        // Single file (image or PDF)
        let pathExt = inputURL.pathExtension.lowercased()
        if pathExt == "pdf" {
            // PDF handling: produce a JSON with "pages" array and "dpi"
            guard let pdf = PDFDocument(url: inputURL) else {
                fputs("Error opening PDF: \(inputPath)\n", stderr)
                return 1
            }

            var pagesArray: [[String: Any]] = []
            let pageCount = pdf.pageCount

            var dpiX: NSDecimalNumber = NSDecimalNumber.zero
            var dpiY: NSDecimalNumber = NSDecimalNumber.zero

            let startPage = pageRange?.lowerBound ?? 1
            let endPage = pageRange?.upperBound ?? pageCount
            for i in (startPage-1)...(endPage-1) {
                print("Processing page \(i+1) of \(pageCount)...")
                guard let page = pdf.page(at: i) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)

                let scale: CGFloat = 2.0
                let renderSize = CGSize(
                    width: max(1, pageBounds.width * scale),
                    height: max(1, pageBounds.height * scale)
                )
                let thumb = page.thumbnail(of: renderSize, for: .mediaBox)
                guard let cgImg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    fputs("Failed to render page \(i+1) of PDF.\n", stderr)
                    continue
                }

                // Compute DPI from first page
                if i == 0 {
                    let rawDpiX = Double(cgImg.width)  / (Double(pageBounds.width)  / 72.0)
                    let rawDpiY = Double(cgImg.height) / (Double(pageBounds.height) / 72.0)
                    dpiX = round3(rawDpiX)
                    dpiY = round3(rawDpiY)
                }

                if let ocrResult = performOCR(cgImage: cgImg, languages: languages) {
                    var pageDict = ocrResult
                    pageDict["page"] = i + 1
                    pagesArray.append(pageDict)
                }
            }

            let pdfOutput: [String: Any] = [
                "pages": pagesArray,
                "dpi": ["x": dpiX, "y": dpiY]
            ]

            let finalOutputPath: String
            if let out = outputPath {
                if out.lowercased().hasSuffix(".json") {
                    finalOutputPath = out
                } else {
                    finalOutputPath = (out as NSString).appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_pdf_output.json")
                }
            } else {
                finalOutputPath = inputURL.deletingPathExtension().path + "_pdf_output.json"
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: pdfOutput, options: [.prettyPrinted])
                try jsonData.write(to: URL(fileURLWithPath: finalOutputPath))
                print("✅ PDF OCR data written to \(finalOutputPath)")
            } catch {
                fputs("Error writing PDF JSON: \(error.localizedDescription)\n", stderr)
                return 1
            }
        } else {
            // single image file (jpg/png)
            guard let ocrResult = performOCR(on: inputPath, languages: languages) else {
                return 1
            }

            let filename = inputURL.deletingPathExtension().lastPathComponent
            let outputFile: String
            if let out = outputPath {
                // if out looks like a directory (doesn't end with .json), treat as directory
                if out.lowercased().hasSuffix(".json") {
                    outputFile = out
                } else {
                    outputFile = (out as NSString).appendingPathComponent(filename + ".json")
                }
            } else {
                outputFile = (inputURL.deletingLastPathComponent().path as NSString).appendingPathComponent(filename + ".json")
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: ocrResult, options: [.prettyPrinted])
                try jsonData.write(to: URL(fileURLWithPath: outputFile))
                print("✅ OCR data written to \(outputFile)")
            } catch {
                fputs("Error writing JSON for \(inputPath): \(error.localizedDescription)\n", stderr)
                return 1
            }
        }
    }

    return 0
}

if #available(macOS 15.0, *) {
    exit(main(args: CommandLine.arguments))
} else {
    fputs("This tool requires macOS 13 or newer.\n", stderr)
    exit(1)
}

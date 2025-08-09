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

struct CommandLineOptions {
    var inputPath: String = ""
    var outputPath: String? = nil
    var languages: [String] = ["en"]
    var pageRange: ClosedRange<Int>? = nil
    var showHelp: Bool = false
    var showSupportedLanguages: Bool = false
}

func parseCommandLineArguments(_ args: [String]) -> CommandLineOptions? {
    var options = CommandLineOptions()
    var i = 1 // Skip program name
    
    while i < args.count {
        let arg = args[i]
        
        switch arg {
        case "-h", "--help":
            options.showHelp = true
            return options
            
        case "--supported-languages":
            options.showSupportedLanguages = true
            return options
            
        case "-l", "--language", "--languages":
            guard i + 1 < args.count else {
                fputs("Error: \(arg) requires a value\n", stderr)
                return nil
            }
            i += 1
            options.languages = args[i].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            
        case "-o", "--output":
            guard i + 1 < args.count else {
                fputs("Error: \(arg) requires a value\n", stderr)
                return nil
            }
            i += 1
            options.outputPath = args[i]
            
        case "-p", "--pages":
            guard i + 1 < args.count else {
                fputs("Error: \(arg) requires a value\n", stderr)
                return nil
            }
            i += 1
            let parts = args[i].split(separator: "-").compactMap { Int($0) }
            if parts.count == 2, parts[0] > 0, parts[1] >= parts[0] {
                options.pageRange = parts[0]...parts[1]
            } else {
                fputs("Error: Invalid page range format. Use format like '2-5'\n", stderr)
                return nil
            }
            
        default:
            if arg.hasPrefix("-") {
                fputs("Error: Unknown option '\(arg)'\n", stderr)
                return nil
            } else {
                // This should be the input path
                if options.inputPath.isEmpty {
                    options.inputPath = arg
                } else {
                    fputs("Error: Multiple input paths specified\n", stderr)
                    return nil
                }
            }
        }
        
        i += 1
    }
    
    return options
}

func printUsage() {
    print("""
    macOCR - OCR tool for images and PDFs using macOS Vision framework
    
    USAGE:
        macOCR [OPTIONS] <input_path>
    
    OPTIONS:
        -l, --language <languages>      Comma-separated list of language codes (default: en)
        -o, --output <path>             Output file or directory path
        -p, --pages <range>             Page range for PDFs (e.g., 2-5)
        -h, --help                      Show this help message
        --supported-languages           List all supported recognition languages
    
    EXAMPLES:
        macOCR image.jpg
        macOCR --language en,es --output results.json document.pdf
        macOCR --language en --pages 1-3 --output output/ document.pdf
        macOCR --language en,fr,de images_directory/ --output ocr_results/
        macOCR --supported-languages
    
    NOTES:
        - If output path ends with .json, JSON format will be used
        - If output path ends with .txt, plain text format will be used (text only, no coordinates)
        - For directories, if no output is specified, results are saved as 'batch_output.json' in the input directory
        - For single files, if no output is specified, results are saved alongside the input file
        - Page ranges are 1-indexed (first page is page 1)
    """)
}

@available(macOS 15.0, *)
func printSupportedLanguages() {
    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = .accurate
    let langs = (try? request.supportedRecognitionLanguages()) ?? []
    
    if let data = try? JSONSerialization.data(withJSONObject: langs, options: []),
       let langsJson = String(data: data, encoding: .utf8) {
        print("Supported recognition languages:")
        print(langsJson)
    } else {
        print("Error: Could not retrieve supported languages")
    }
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
func writeTextOutput(_ object: [String: Any], to finalOutputPath: String) throws {
    var textLines: [String] = []
    
    // For batch processing (directory of images)
    if let batchData = object as? [String: [String: Any]] {
        let sortedKeys = batchData.keys.sorted { a, b in
            a.localizedStandardCompare(b) == .orderedAscending
        }
        
        for filename in sortedKeys {
            if let fileData = batchData[filename],
               let observations = fileData["observations"] as? [[String: Any]] {
                if !textLines.isEmpty {
                    textLines.append("") // Add blank line between files
                }
                textLines.append("=== \(filename) ===")
                for observation in observations {
                    if let text = observation["text"] as? String {
                        textLines.append(text)
                    }
                }
            }
        }
    }
    // For PDF processing
    else if let pages = object["pages"] as? [[String: Any]] {
        for (index, page) in pages.enumerated() {
            if index > 0 {
                textLines.append("") // Add blank line between pages
            }

            if let observations = page["observations"] as? [[String: Any]] {
                for observation in observations {
                    if let text = observation["text"] as? String {
                        textLines.append(text)
                    }
                }
            }
        }
    }
    // For single image processing
    else if let observations = object["observations"] as? [[String: Any]] {
        for observation in observations {
            if let text = observation["text"] as? String {
                textLines.append(text)
            }
        }
    }
    
    let textContent = textLines.joined(separator: "\n")
    try textContent.write(to: URL(fileURLWithPath: finalOutputPath), atomically: true, encoding: .utf8)
}

@available(macOS 15.0, *)
func main(args: [String]) -> Int32 {
    guard let options = parseCommandLineArguments(args) else {
        return 1
    }
    
    if options.showHelp {
        printUsage()
        return 0
    }
    
    if options.showSupportedLanguages {
        printSupportedLanguages()
        return 0
    }
    
    if options.inputPath.isEmpty {
        fputs("Error: No input path specified\n\n", stderr)
        printUsage()
        return 1
    }

    let inputPath = options.inputPath
    let outputPath = options.outputPath
    let pageRange = options.pageRange
    let languages = options.languages

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
            if out.lowercased().hasSuffix(".json") || out.lowercased().hasSuffix(".txt") {
                finalOutputPath = out
            } else {
                finalOutputPath = (out as NSString).appendingPathComponent("batch_output.json")
            }
        } else {
            finalOutputPath = (inputURL.path as NSString).appendingPathComponent("batch_output.json")
        }

        do {
            if finalOutputPath.lowercased().hasSuffix(".txt") {
                try writeTextOutput(batchOutput, to: finalOutputPath)
                print("✅ Batch OCR text written to \(finalOutputPath)")
            } else {
                try writeJSONObjectOrdered(batchOutput, to: finalOutputPath)
                print("✅ Batch OCR data written to \(finalOutputPath)")
            }
        } catch {
            fputs("Error writing batch output: \(error.localizedDescription)\n", stderr)
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
                if i == (startPage-1) {
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
                if out.lowercased().hasSuffix(".json") || out.lowercased().hasSuffix(".txt") {
                    finalOutputPath = out
                } else {
                    finalOutputPath = (out as NSString).appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_pdf_output.json")
                }
            } else {
                finalOutputPath = inputURL.deletingPathExtension().path + "_pdf_output.json"
            }

            do {
                if finalOutputPath.lowercased().hasSuffix(".txt") {
                    try writeTextOutput(pdfOutput, to: finalOutputPath)
                    print("✅ PDF OCR text written to \(finalOutputPath)")
                } else {
                    let jsonData = try JSONSerialization.data(withJSONObject: pdfOutput, options: [.prettyPrinted])
                    try jsonData.write(to: URL(fileURLWithPath: finalOutputPath))
                    print("✅ PDF OCR data written to \(finalOutputPath)")
                }
            } catch {
                fputs("Error writing PDF output: \(error.localizedDescription)\n", stderr)
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
                // if out looks like a directory (doesn't end with .json or .txt), treat as directory
                if out.lowercased().hasSuffix(".json") || out.lowercased().hasSuffix(".txt") {
                    outputFile = out
                } else {
                    outputFile = (out as NSString).appendingPathComponent(filename + ".json")
                }
            } else {
                outputFile = (inputURL.deletingLastPathComponent().path as NSString).appendingPathComponent(filename + ".json")
            }

            do {
                if outputFile.lowercased().hasSuffix(".txt") {
                    try writeTextOutput(ocrResult, to: outputFile)
                    print("✅ OCR text written to \(outputFile)")
                } else {
                    let jsonData = try JSONSerialization.data(withJSONObject: ocrResult, options: [.prettyPrinted])
                    try jsonData.write(to: URL(fileURLWithPath: outputFile))
                    print("✅ OCR data written to \(outputFile)")
                }
            } catch {
                fputs("Error writing output for \(inputPath): \(error.localizedDescription)\n", stderr)
                return 1
            }
        }
    }

    return 0
}

if #available(macOS 15.0, *) {
    exit(main(args: CommandLine.arguments))
} else {
    fputs("This tool requires macOS 15 or newer.\n", stderr)
    exit(1)
}

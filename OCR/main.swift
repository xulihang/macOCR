import Vision
import Cocoa

@available(macOS 13.0, *)
func performOCR(on imagePath: String, outputDir: String?, languages: [String]) {
    guard let img = NSImage(byReferencingFile: imagePath),
          let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: failed to load or convert image '\(imagePath)'\n", stderr)
        return
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(cgImage: imgRef, options: [:])

    do {
        try handler.perform([request])
    } catch {
        fputs("OCR execution failed for \(imagePath): \(error.localizedDescription)\n", stderr)
        return
    }

    guard let results = request.results else {
        fputs("No text results for \(imagePath).\n", stderr)
        return
    }

    var output: [[String: Any]] = []

    for observation in results {
        var obsEntry: [String: Any] = [:]
        var candidatesArray: [[String: Any]] = []

        let candidates = observation.topCandidates(5)
        for candidate in candidates {
            var candidateDict: [String: Any] = [
                "text": candidate.string,
                "confidence": candidate.confidence
            ]

            let range = candidate.string.startIndex..<candidate.string.endIndex
            if let box = try? candidate.boundingBox(for: range)?.boundingBox {
                candidateDict["boundingBox"] = [
                    "x": box.origin.x,
                    "y": box.origin.y,
                    "width": box.size.width,
                    "height": box.size.height
                ]
            }

            candidatesArray.append(candidateDict)
        }

        obsEntry["candidates"] = candidatesArray

        let box = observation.boundingBox
        obsEntry["observationBoundingBox"] = [
            "x": box.origin.x,
            "y": box.origin.y,
            "width": box.size.width,
            "height": box.size.height
        ]

        output.append(obsEntry)
    }

    let inputURL = URL(fileURLWithPath: imagePath)
    let filename = inputURL.deletingPathExtension().lastPathComponent
    let outputFile = (outputDir ?? inputURL.deletingLastPathComponent().path) + "/" + filename + ".json"

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
        try jsonData.write(to: URL(fileURLWithPath: outputFile))
        print("✅ OCR data written to \(outputFile)")
    } catch {
        fputs("Error writing JSON for \(imagePath): \(error.localizedDescription)\n", stderr)
    }
}

@available(macOS 13.0, *)
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
          macOCR languages image_or_directory_path [output_directory]

        example:
          macOCR en ./image.jpg
          macOCR en ./images/ ./ocr_output/

        If output_directory is not provided, output is saved next to the input image(s).
        """)
        return 1
    }

    let languageArg = args[1]
    let inputPath = args[2]
    let outputPath = args.count > 3 ? args[3] : nil
    let languages = languageArg.split(separator: ",").map { String($0) }

    var isDir: ObjCBool = false
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: inputPath, isDirectory: &isDir), isDir.boolValue {
        guard let files = try? fileManager.contentsOfDirectory(atPath: inputPath) else {
            fputs("Error reading directory: \(inputPath)\n", stderr)
            return 1
        }

        for file in files where file.lowercased().hasSuffix(".jpg") || file.lowercased().hasSuffix(".jpeg") || file.lowercased().hasSuffix(".png") {
            let fullPath = (inputPath as NSString).appendingPathComponent(file)
            performOCR(on: fullPath, outputDir: outputPath, languages: languages)
        }
    } else {
        performOCR(on: inputPath, outputDir: outputPath, languages: languages)
    }

    return 0
}

if #available(macOS 13.0, *) {
    exit(main(args: CommandLine.arguments))
} else {
    fputs("This tool requires macOS 13 or newer.\n", stderr)
    exit(1)
}

import Vision
import Cocoa

@available(macOS 13.0, *)
func performOCR(on imagePath: String, languages: [String]) -> [String: Any]? {
    guard let img = NSImage(byReferencingFile: imagePath),
          let imgRef = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: failed to load or convert image '\(imagePath)'\n", stderr)
        return nil
    }

    let imageWidth = CGFloat(imgRef.width)
    let imageHeight = CGFloat(imgRef.height)

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
        return nil
    }

    guard let results = request.results else {
        fputs("No text results for \(imagePath).\n", stderr)
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
                "x": absBox.origin.x,
                "y": flippedY,
                "width": absBox.size.width,
                "height": absBox.size.height
            ]
        ])
    }

    return [
        "width": Int(imageWidth),
        "height": Int(imageHeight),
        "observations": observations
    ]
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
    let inputURL = URL(fileURLWithPath: inputPath)

    if fileManager.fileExists(atPath: inputPath, isDirectory: &isDir), isDir.boolValue {
        guard let files = try? fileManager.contentsOfDirectory(atPath: inputPath) else {
            fputs("Error reading directory: \(inputPath)\n", stderr)
            return 1
        }

        var batchOutput: [String: Any] = [:]

        for file in files where file.lowercased().hasSuffix(".jpg") || file.lowercased().hasSuffix(".jpeg") || file.lowercased().hasSuffix(".png") {
            let fullPath = (inputPath as NSString).appendingPathComponent(file)
            if let ocrResult = performOCR(on: fullPath, languages: languages) {
                batchOutput[file] = ocrResult
            }
        }

        let finalOutputPath = (outputPath ?? inputURL.path) + "/batch_output.json"
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: batchOutput, options: [.prettyPrinted])
            try jsonData.write(to: URL(fileURLWithPath: finalOutputPath))
            print("✅ Batch OCR data written to \(finalOutputPath)")
        } catch {
            fputs("Error writing batch JSON: \(error.localizedDescription)\n", stderr)
            return 1
        }
    } else {
        guard let ocrResult = performOCR(on: inputPath, languages: languages) else {
            return 1
        }

        let filename = inputURL.deletingPathExtension().lastPathComponent
        let outputFile = (outputPath ?? inputURL.deletingLastPathComponent().path) + "/" + filename + ".json"

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: ocrResult, options: [.prettyPrinted])
            try jsonData.write(to: URL(fileURLWithPath: outputFile))
            print("✅ OCR data written to \(outputFile)")
        } catch {
            fputs("Error writing JSON for \(inputPath): \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    return 0
}

if #available(macOS 13.0, *) {
    exit(main(args: CommandLine.arguments))
} else {
    fputs("This tool requires macOS 13 or newer.\n", stderr)
    exit(1)
}

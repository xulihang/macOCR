# macOCR

A high-performance Swift command-line tool that leverages Apple's [Vision framework](https://developer.apple.com/documentation/vision) to perform accurate OCR on images and PDF documents. Outputs structured JSON with precise bounding boxes or clean plain text, perfect for integration with automation workflows, data processing pipelines, and downstream applications.

## ✨ Features

- **High Accuracy OCR**: Uses `VNRecognizeTextRequestRevision3` for maximum text recognition accuracy
- **Multi-Language Support**: Supports all Vision framework languages including RTL languages (Arabic, Hebrew)
- **Flexible Input**: Process single images, entire directories, or specific PDF page ranges
- **Multiple Output Formats**:
  - JSON with bounding boxes and metadata
  - Plain text for simple text extraction
- **Batch Processing**: Process entire directories into consolidated output files
- **PDF Support**: Extract text from PDFs with optional page range selection
- **Precise Coordinates**: Bounding boxes with 3-decimal precision and flipped Y-axis for standard coordinate systems
- **Natural Sorting**: Intelligent file ordering (e.g., "2.jpg" before "10.jpg")

## 🔧 Requirements

- **macOS 15.0+** (Sequoia or later)
- **Swift 5.7+**
- **Xcode 16+** (for building)
- Apple Silicon or Intel Mac with Vision framework support

## 📦 Installation

### Option 1: Download Release Binary

1. Download the latest release from the [Releases page](https://github.com/ragaeeb/macOCR/releases)
2. Extract and move to your PATH:
   ```bash
   unzip macOCR.zip
   sudo mv macOCR /usr/local/bin/
   ```

### Option 2: Build from Source

```bash
git clone https://github.com/ragaeeb/macOCR.git
cd macOCR
swift build -c release
# Binary will be at .build/release/macOCR
```

## 🚀 Usage

```bash
macOCR [OPTIONS] <input_path>
```

### Command-Line Options

| Option                   | Description                       | Example                 |
| ------------------------ | --------------------------------- | ----------------------- |
| `-l, --language <codes>` | Comma-separated language codes    | `--language en,es,fr`   |
| `-o, --output <path>`    | Output file or directory          | `--output results.json` |
| `-p, --pages <range>`    | PDF page range (1-indexed)        | `--pages 1-5`           |
| `-h, --help`             | Show comprehensive help           |                         |
| `--supported-languages`  | List all available language codes |                         |

### Input Formats

- **Images**: `.jpg`, `.jpeg`, `.png`
- **Documents**: `.pdf` (with optional page ranges)
- **Directories**: Batch process all supported images

### Output Formats

- **JSON** (`.json`): Complete OCR data with bounding boxes
- **Text** (`.txt`): Plain text content only

## 📋 Examples

### Basic Image OCR

```bash
# Process single image with default settings
macOCR image.jpg
# → Creates image.json

# Extract text only
macOCR --output text_only.txt image.jpg
```

### Multi-Language Processing

```bash
# OCR with multiple languages
macOCR --language en,es,ar document.pdf --output results.json

# Arabic and English text recognition
macOCR --language ar,en arabic_document.png
```

### PDF Processing

```bash
# Process entire PDF
macOCR document.pdf

# Process specific page range
macOCR --pages 1-10 --language en,fr report.pdf --output chapter1.json

# Extract text from PDF pages
macOCR --pages 5-8 --output extracted.txt manual.pdf
```

### Batch Directory Processing

```bash
# Process all images in directory
macOCR images_folder/ --output batch_results/

# Multi-language batch with specific output
macOCR --language en,zh scanned_docs/ --output multilang_output.json
```

### Language Discovery

```bash
# List all supported languages
macOCR --supported-languages
# → Displays JSON array of language codes
```

## 📊 Output Structure

### Single Image JSON

```json
{
  "width": 1200,
  "height": 800,
  "observations": [
    {
      "text": "Detected text content",
      "bbox": {
        "x": 123.456,
        "y": 78.901,
        "width": 234.567,
        "height": 45.678
      }
    }
  ]
}
```

### PDF Document JSON

```json
{
  "pages": [
    {
      "page": 1,
      "width": 1200,
      "height": 800,
      "observations": [
        {
          "text": "Page 1 content",
          "bbox": { "x": 100.0, "y": 50.0, "width": 200.0, "height": 30.0 }
        }
      ]
    }
  ],
  "dpi": { "x": 144.0, "y": 144.0 }
}
```

### Batch Processing JSON

```json
{
  "image1.jpg": {
    "width": 800,
    "height": 600,
    "observations": [...]
  },
  "image2.png": {
    "width": 1024,
    "height": 768,
    "observations": [...]
  }
}
```

## 🌍 Language Support

macOCR supports all languages available in Apple's Vision framework. Common language codes include:

- **English**: `en`
- **Spanish**: `es`
- **French**: `fr`
- **German**: `de`
- **Chinese**: `zh-Hans` (Simplified), `zh-Hant` (Traditional)
- **Japanese**: `ja`
- **Korean**: `ko`
- **Arabic**: `ar`
- **Hebrew**: `he`
- **Russian**: `ru`
- **Portuguese**: `pt`
- **Italian**: `it`

Use `macOCR --supported-languages` to get the complete list of available codes for your system.

## 🔧 Technical Details

### Coordinate System

- **Bounding boxes** use absolute pixel coordinates
- **Y-axis** is flipped to match standard top-down origin (0,0 at top-left)
- **Precision** is exactly 3 decimal places for all measurements
- **Units** are in pixels relative to the source image dimensions

### PDF Processing

- **Rendering scale**: 2x for improved text recognition accuracy
- **DPI calculation**: Automatically computed and included in output
- **Page indexing**: 1-based (first page is page 1)
- **Memory efficient**: Processes pages individually

### Performance Characteristics

- **Recognition level**: Accurate (highest quality)
- **Language correction**: Disabled for more predictable output
- **Batch processing**: Natural filename sorting with progress indication
- **Error handling**: Graceful failure with detailed error messages

## 🛠️ Build & Development

### Building Release Binary

#### From Xcode (Recommended for production):

1. Open the project in Xcode
2. Go to `Product > Scheme > Edit Scheme`
3. Under **Run** or **Archive**, ensure the build configuration is set to **Release**
4. Use `CMD + B` to build, or go to `Product > Archive`
5. Export the built binary via `Organizer > Distribute Content`

#### From Terminal:

```bash
swift build -c release
# Resulting binary will be at .build/release/macOCR
```

### Development Setup

```bash
git clone https://github.com/ragaeeb/macOCR.git
cd macOCR
swift build
.build/debug/macOCR --help
```

### Running Tests

```bash
swift test
```

## 🔒 Code Signing & Distribution

### ✅ 1. Build the Production Binary

Follow the build instructions above to create your release binary.

### 🔏 2. Code Sign the Binary

First, verify your Developer ID certificate is installed:

```bash
security find-identity -v -p codesigning
```

Then sign your binary:

```bash
codesign --timestamp --options runtime --sign "Developer ID Application: YOUR NAME (TEAMID)" ./macOCR
```

Or use the certificate hash:

```bash
codesign --timestamp --options runtime --sign E0F5D47B058F455216F3E2BA3D6EA58E07453C32 ./macOCR
```

**Important**: If you get "already signed" error, remove the existing signature first:

```bash
codesign --remove-signature /path/to/your/binary
```

**Verify the signature**:

```bash
codesign --verify --deep --strict --verbose=2 ./macOCR
```

### 📦 3. Create a Zip Archive

```bash
ditto -c -k --keepParent ./macOCR macOCR.zip
```

### 🧾 4. Submit for Notarization

```bash
xcrun notarytool submit macOCR.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait
```

Expected output should end with:

```
status: Accepted
```

### 🧪 5. Confirm Notarization

To double-check the notarization status:

```bash
xcrun notarytool log <submission-id>
```

### 🚫 What **Not** to Do for CLI Binaries

- ❌ **Do not run** `stapler staple` on the binary. It only works for `.app`, `.pkg`, or `.dmg` files
- ❌ **Do not rely on** `spctl` for binaries. It will show:
  ```
  the code is valid but does not seem to be an app
  ```
  This is expected for CLI tools and doesn't indicate an error.

### 🧰 Troubleshooting

#### I see two Developer IDs in `security find-identity`

This is common if you've imported the same certificate twice. It's harmless, but you can attempt to delete duplicates:

```bash
security delete-identity -c "Developer ID Application: Your Name" login
```

> 🔸 May fail due to permissions; you can ignore unless it's causing conflicts.

#### `stapler` fails with error 73

**Expected behavior**. CLI binaries don't get stapled—only app bundles do.

#### `spctl` rejects my binary

**Expected behavior**. `spctl` is designed for apps, not CLI tools. Your notarized binary will work correctly.

#### "This tool requires macOS 15 or newer"

- Update to macOS Sequoia (15.0) or later
- Check system version with `sw_vers`

#### "Error opening PDF" or "Failed to render page X of PDF"

- Verify PDF is not corrupted or password-protected
- Check file permissions and path accessibility
- Try processing individual page ranges for large PDFs

### 📦 Final Distribution Notes

- You can now distribute the `macOCR.zip` safely
- On first run, macOS will verify notarization **online**
- Users may see a security dialog on first launch—this is normal for notarized CLI tools

## 📋 Use Cases

### Document Digitization

- Convert scanned documents to searchable text
- Extract content from PDF forms and reports
- Digitize historical documents and archives

### Data Extraction

- Process receipts and invoices for accounting
- Extract text from screenshots and images
- Convert handwritten notes to digital text

### Automation & Integration

- Integrate with CI/CD pipelines for document processing
- Batch process large document collections
- Feed extracted text to other analysis tools

### Multi-Language Documents

- Process international documents with mixed languages
- Handle RTL languages like Arabic and Hebrew
- Support for Asian languages (Chinese, Japanese, Korean)

## ⚠️ Important Notes

### System Requirements

- **macOS Version**: 15.0+ required (uses latest Vision APIs)
- **Hardware**: Apple Silicon recommended for best performance
- **Memory**: Sufficient RAM for image processing (varies by image size)

### File Format Support

- **Images**: Standard formats (JPEG, PNG) - no HEIC support currently
- **PDFs**: Vector and raster PDFs supported
- **Directories**: Recursive processing not supported (single level only)

### Output Behavior

- **Default locations**: Output saved alongside input files if no output specified
- **Directory outputs**: Creates `batch_output.json` by default
- **Filename conflicts**: Will overwrite existing output files
- **Text extraction**: Preserves original text order and line breaks

## 🐛 Troubleshooting

### Common Issues

**"No text results for image"**

- Image may not contain recognizable text
- Try different language codes
- Ensure image quality is sufficient for OCR

### Performance Optimization

- **Large PDFs**: Use page ranges (`--pages`) to process sections
- **Batch processing**: Process directories in smaller chunks if memory constrained
- **Image quality**: Higher resolution images generally produce better results
- **Language selection**: Limit to relevant languages for better accuracy

## 📈 Exit Codes

| Code | Meaning                                                          |
| ---- | ---------------------------------------------------------------- |
| `0`  | Success - OCR completed normally                                 |
| `1`  | Error - Invalid arguments, file not found, or processing failure |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Swift naming conventions
- Add comprehensive documentation for new functions
- Include error handling for all file operations
- Test with various image formats and languages
- Update help text and README for new features

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgements

- **Apple Vision Framework**: Core OCR functionality
- **Original Project**: Forked from [xulihang/macOCR](https://github.com/xulihang/macOCR)
- **Community**: Contributors and issue reporters

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/ragaeeb/macOCR/issues)

---

**Made with ❤️ for the macOS community**
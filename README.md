# macOCR

A minimal Swift command-line tool that uses Apple's [Vision framework](https://developer.apple.com/documentation/vision) to perform high-accuracy OCR on images and export structured JSON output. Ideal for integration with Node.js or other systems for downstream processing.

## Features

- Leverages `VNRecognizeTextRequestRevision3` for improved accuracy.
- Outputs structured JSON including:
  - Top OCR candidate text only
  - Bounding box geometry (with Y-axis flipped correctly)
- Automatically detects supported OCR languages
- Supports individual images or whole directories
- Batch processes entire folders into a single consolidated JSON file
- Supports RTL languages like Arabic
- Outputs `.json` files named after the input image or a single `batch_output.json` for directories

## Requirements

- macOS 13+
- Swift 5.7+
- Xcode 14+

## Usage

```sh
macOCR <languages> <image_path|directory_path> [output_dir]
```

### Examples

#### OCR a single image:

```sh
macOCR en ./page1.jpg ./output/
```

Produces `./output/page1.json`.

#### OCR all images in a directory:

```sh
macOCR en ./scanned_pages/ ./output/
```

Produces a single file `./output/batch_output.json` with structure:

```json
{
  "page1.jpg": {
    "width": 1000,
    "height": 1500,
    "observations": [
      { "text": "example", "bbox": { "x": 123, "y": 456, "width": 78, "height": 90 } }
    ]
  },
  "page2.jpg": {
    ...
  }
}
```

#### Show help (and list of supported languages):

```sh
macOCR
```

## Output Format

- Each output includes:
  - `width`, `height` of the image
  - `observations`, where each observation contains:
    - `text` (top candidate only)
    - `bbox` (bounding box with flipped Y coordinate)

Each `.json` file will contain an array of OCR blocks, for example:

```json
[
  {
    "bbox": { "x": ..., "y": ..., "width": ..., "height": ... },
    "text": "Sample text"
  },
  ...
]
```

## Notes

- Bounding boxes are provided with pixel coordinates relative to the actual image size.
- Flipped Y-coordinate to match top-down origin.
- No confidence scores or multiple candidates are output.

## Build

### Release build (Recommended for production):

From Xcode:

1. Open the project in Xcode
2. Go to `Product > Archive`
3. Export the built binary via `Organizer > Distribute Content`

From terminal:

```sh
swift build -c release
```

Resulting binary will be in:

```
.build/release/macOCR
```

## 🔒 Releasing & Notarizing the macOCR CLI Tool

This section documents the **complete process** for code-signing, notarizing, and preparing your `macOCR` Swift command-line tool for distribution. It includes detailed steps as well as common troubleshooting tips.

---

### ✅ 1. Build the Production Binary in Xcode

1. Open your Xcode project.
2. Go to `Product > Scheme > Edit Scheme`.
3. Under **Run** or **Archive**, ensure the build configuration is set to **Release**.
4. Use:
   ```bash
   CMD + B
   ```
   to build, or go to:
   ```
   Product > Archive
   ```

---

### 🔏 2. Code Sign the Binary

Make sure your Developer ID certificate is installed and visible:

```bash
security find-identity -v -p codesigning
```

Then sign your binary:

```bash
codesign --timestamp --options runtime --sign "Developer ID Application: YOUR NAME (TEAMID)" ./OCR
```

Or use the certificate hash:

```bash
codesign --timestamp --options runtime --sign E0F5D47B058F455216F3E2BA3D6EA58E07453C32 ./OCR
```

`IMPORTANT`: If it says already signed, then this is because XCode automatically signs it, so you may need to remove the signature first then resign:
codesign --remove-signature `/Users/.../Library/Developer/Xcode/DerivedData/OCR-cnhwvhkmntjhlffvhbrehkvrqyyf/Build/Products/Release/OCR`

**Verify the signature**:

```bash
codesign --verify --deep --strict --verbose=2 ./OCR
```

---

### 📦 3. Create a Zip Archive

```bash
ditto -c -k --keepParent ./OCR OCR.zip
```

---

### 🧾 4. Submit for Notarization

```bash
xcrun notarytool submit OCR.zip \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "your-app-specific-password" \
  --wait
```

Expected output should end in:

```
status: Accepted
```

---

### 🧪 5. Confirm Notarization

To double-check:

```bash
xcrun notarytool log <submission-id>
```

---

### 🚫 What **Not** to Do for CLI Binaries

- ❌ Do not run `stapler staple` on the binary. It only works for `.app`, `.pkg`, or `.dmg`.
- ❌ Do not rely on `spctl` for binaries. It will show:
  ```
  the code is valid but does not seem to be an app
  ```

This is expected for CLI tools and doesn't indicate an error.

---

### 🧰 Troubleshooting

#### I see two Developer IDs in `security find-identity`

This is common if you've imported the same certificate twice. It's harmless, but you can attempt to delete one via:

```bash
security delete-identity -c "Developer ID Application: Your Name" login
```

> 🔸 May fail due to permissions; you can ignore unless it's causing conflict.

#### `stapler` fails with error 73

Expected. CLI binaries don't get stapled.

#### `spctl` rejects my binary

Expected. `spctl` is for apps, not CLI tools.

---

### 📦 Final Notes

- You can now distribute the `OCR.zip` safely.
- On first run, macOS will verify its notarization **online**.

## License

MIT

## Acknowledgements

Initial project fork from: https://github.com/xulihang/macOCR

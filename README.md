# macOCR
Command line OCR tool using macOS's VNRecognizeTextRequest and Live Text (VisionKit)

```
usage:
    language mode languageCorrection [wordLevel] image_path output_path
    mode: fast/true (快速), accurate/false (精确, 默认), livetext (Live Text, macOS 13+)
    --langs [fast|accurate|livetext]: list suppported languages

example:
    ./OCR en-US,zh-Hans false true ./image.jpg out.json
    ./OCR en-US,zh-Hans livetext true ./image.jpg out.json
```

`mode` 支持三种取值：

| 取值 | 说明 |
| --- | --- |
| `fast` 或 `true` | 使用 `VNRecognizeTextRequest` 的快速级别 |
| `accurate` 或 `false` | 使用 `VNRecognizeTextRequest` 的精确级别（默认） |
| `livetext` | 使用 VisionKit 的 Live Text，需要 macOS 13+ |

Live Text 模式下的坐标来自 `VKQuad`，与 Vision 模式一样会同时输出四个顶点
（`x0,y0` ~ `x3,y3`，顺时针：左上、右上、右下、左下）以及 `x/y/width/height`
包围盒，输出 JSON 的结构与 Vision 模式完全一致，可直接替换使用。

## GUI Frontend

[ImageTrans](https://www.basiccat.org/imagetrans/)

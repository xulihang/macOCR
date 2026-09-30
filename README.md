# macOCR
Command line OCR tool using macOS's VNRecognizeTextRequest and Live Text (VisionKit)

```
usage:
    language mode languageCorrection [wordLevel] image_path output_path
    mode: fast/true (快速), accurate/false (精确, 默认), livetext (Live Text, macOS 13+, 不支持时回退到 accurate)
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

`livetext` 在系统不支持时会**自动回退到 `accurate`**（并在 stderr 打印一条
`Warning: ... falling back to accurate mode`），因此可以直接作为默认引擎使用。
ImageTrans 插件就是这么做的。系统不支持的情形包括：macOS 低于 13、或者
运行环境里取不到 `VKCImageAnalyzer` 私有类。

Live Text 模式下的坐标来自 `VKQuad`，与 Vision 模式一样会同时输出四个顶点
（`x0,y0` ~ `x3,y3`，顺时针：左上、右上、右下、左下）以及 `x/y/width/height`
包围盒，输出 JSON 的结构与 Vision 模式完全一致，可直接替换使用。

> 注意：Live Text 的 `locales` 只作为语言提示，**不会像 `recognitionLanguages`
> 那样过滤识别结果**——它仍会自动识别画面中的其他文种（例如指定 `ar-SA` 也能
> 识别出竖排日文）。如果必须严格限定语言，请使用 `accurate`。

## GUI Frontend

[ImageTrans](https://www.basiccat.org/imagetrans/)

# Selfie segmentation model

`selfie_segmentation.onnx` is a MobileNetV3 person/background segmenter
(256×256, NCHW float32 `pixel_values` → `alphas`). It runs on the Windows
Production video path via inbox WinML.

Inbox WinML on Windows 11 accepts ONNX IR ≤ 9. The upstream export is IR 10
with HardSwish (opset 14). `downgrade_ir.py` rewrites HardSwish to
Add/Clip/Mul and sets IR 9 / opset 13 so `LearningModel::LoadFromFilePath`
succeeds.

License: Apache 2.0.

- Conversion: [onnx-community/mediapipe_selfie_segmentation](https://huggingface.co/onnx-community/mediapipe_selfie_segmentation)
- Original: Google MediaPipe Selfie Segmentation (Apache 2.0)

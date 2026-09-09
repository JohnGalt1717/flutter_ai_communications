# Selfie segmentation model

`selfie_segmentation.onnx` is a MobileNetV3 person/background segmenter
(256×256, NCHW float32 `pixel_values` → `alphas`). It runs on the Linux
Production video path via ONNX Runtime when `libonnxruntime` is present.

License: Apache 2.0.

- Conversion: [onnx-community/mediapipe_selfie_segmentation](https://huggingface.co/onnx-community/mediapipe_selfie_segmentation)
- Original: Google MediaPipe Selfie Segmentation (Apache 2.0)

#!/usr/local/bin/python3
import sys
import os
import numpy as np
from PIL import Image, ImageOps
import onnxruntime as ort

def find_default_model():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "rmbg-1.4.onnx"),
        os.path.join(script_dir, "..", "Resources", "rmbg-1.4.onnx"),
        "/Users/ivanlevy/Desktop/DynamicNotch/rmbg-1.4.onnx",
        os.path.join(script_dir, "u2netp.onnx"),
        os.path.join(script_dir, "..", "Resources", "u2netp.onnx"),
        "/Users/ivanlevy/Desktop/DynamicNotch/u2netp.onnx",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def remove_background(input_path: str, output_path: str, model_path: str = None):
    if not model_path or not os.path.isfile(model_path):
        model_path = find_default_model()
    
    if not model_path or not os.path.isfile(model_path):
        raise FileNotFoundError(f"No background removal ONNX model found at {model_path}")

    # 1. Open image and handle EXIF rotation
    orig_img = Image.open(input_path)
    orig_img = ImageOps.exif_transpose(orig_img)
    orig_w, orig_h = orig_img.size

    # 2. Composite onto neutral canvas if image already has alpha channel
    if orig_img.mode in ("RGBA", "LA") or (orig_img.mode == "P" and "transparency" in orig_img.info):
        rgba_conv = orig_img.convert("RGBA")
        bg = Image.new("RGB", rgba_conv.size, (255, 255, 255))
        bg.paste(rgba_conv, mask=rgba_conv.split()[3])
        rgb_for_model = bg
    else:
        rgb_for_model = orig_img.convert("RGB")

    # 3. Setup ONNX runtime session with multithreading
    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = min(8, os.cpu_count() or 4)
    sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    session = ort.InferenceSession(model_path, sess_options=sess_opts, providers=["CPUExecutionProvider"])
    input_tensor_meta = session.get_inputs()[0]
    input_name = input_tensor_meta.name
    input_shape = input_tensor_meta.shape

    target_h = input_shape[2] if (len(input_shape) > 2 and isinstance(input_shape[2], int)) else 1024
    target_w = input_shape[3] if (len(input_shape) > 3 and isinstance(input_shape[3], int)) else 1024

    # 4. Preprocess input
    rgb_resized = rgb_for_model.resize((target_w, target_h), Image.Resampling.BILINEAR)
    im_ary = np.array(rgb_resized, dtype=np.float32) / 255.0

    if target_h == 1024 and target_w == 1024:
        # State-of-the-Art RMBG-1.4 normalization: (im / 255.0) - 0.5
        im_ary = im_ary - 0.5
    else:
        # Standard U2-Net normalization
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        im_ary = (im_ary - mean) / std

    # HWC -> NCHW
    tensor = np.transpose(im_ary, (2, 0, 1))[np.newaxis, :, :, :].astype(np.float32)

    # 5. Run Inference
    outputs = session.run(None, {input_name: tensor})
    pred = outputs[0][0, 0, :, :]

    # 6. Min-Max Normalization
    ma = float(np.max(pred))
    mi = float(np.min(pred))
    if ma - mi > 1e-5:
        pred = (pred - mi) / (ma - mi)
    else:
        pred = np.zeros_like(pred)

    # 7. Sub-pixel Edge Cleanup & Noise Suppression
    if target_h == 1024 and target_w == 1024:
        # RMBG-1.4: Eliminate residual noise (<0.015 -> 0), solidify subject (>0.985 -> 1)
        pred = np.where(pred < 0.015, 0.0, pred)
        pred = np.where(pred > 0.985, 1.0, pred)
    else:
        pred = np.clip((pred - 0.12) / 0.76, 0.0, 1.0)

    mask_u8 = (pred * 255.0).astype(np.uint8)

    # 8. Scale mask back to original resolution with bilinear interpolation
    mask_img = Image.fromarray(mask_u8, mode="L").resize((orig_w, orig_h), Image.Resampling.BILINEAR)

    # 9. Final RGBA composition
    orig_rgba = np.array(orig_img.convert("RGBA"), dtype=np.uint8)
    alpha_arr = np.array(mask_img, dtype=np.uint8)

    # If original image had pre-existing transparency, keep it transparent
    if "A" in orig_img.getbands():
        orig_alpha = np.array(orig_img.getchannel("A"), dtype=np.uint8)
        alpha_arr = np.minimum(alpha_arr, orig_alpha)

    orig_rgba[:, :, 3] = alpha_arr

    # Zero out RGB where alpha is zero to ensure pristine PNG compression and no edge halos
    zero_mask = (alpha_arr == 0)
    orig_rgba[zero_mask, 0] = 0
    orig_rgba[zero_mask, 1] = 0
    orig_rgba[zero_mask, 2] = 0

    out_img = Image.fromarray(orig_rgba, mode="RGBA")
    out_img.save(output_path, format="PNG", optimize=True)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: remove_bg_ai.py <input_image> <output_png> [model_path]")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    model_path = sys.argv[3] if len(sys.argv) > 3 else None
    
    try:
        remove_background(input_path, output_path, model_path)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

"""
Fine-tuned 모델 → ONNX 변환 + 양자화
=====================================
학습된 PyTorch 체크포인트를 ONNX로 변환하고,
INT8 동적 양자화로 크기를 줄입니다.

사용법:
    python export_onnx.py --checkpoint checkpoints/checkpoint_best.pt
    python export_onnx.py --checkpoint checkpoints/checkpoint_best.pt --quantize
    python export_onnx.py --checkpoint checkpoints/checkpoint_best.pt --output assets/models/doc_aligner_book.onnx
"""

import argparse
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch
from onnx2torch import convert


def load_model(onnx_path: str, checkpoint_path: str, device: str = "cpu"):
    """ONNX 원본 + 학습된 가중치 로드"""
    print(f"모델 로드 중...")
    print(f"  원본 ONNX: {onnx_path}")
    print(f"  체크포인트: {checkpoint_path}")

    # ONNX → PyTorch 변환
    onnx_model = onnx.load(onnx_path)
    model = convert(onnx_model)

    # 학습된 가중치 로드
    ckpt = torch.load(checkpoint_path, map_location=device, weights_only=False)
    model.load_state_dict(ckpt["model"])
    model.eval()

    print(f"  Epoch: {ckpt['epoch'] + 1}")
    print(f"  Best val dist: {ckpt.get('best_val_dist', 'N/A')}")

    return model


def export_onnx(model, output_path: str, device: str = "cpu"):
    """PyTorch → ONNX 변환"""
    model = model.to(device).eval()
    dummy = torch.randn(1, 3, 256, 256, device=device)

    print(f"\nONNX export 중...")
    torch.onnx.export(
        model,
        dummy,
        output_path,
        input_names=["img"],
        output_names=["points", "has_obj"],
        opset_version=16,
        dynamic_axes={
            "img": {0: "batch"},
            "points": {0: "batch"},
            "has_obj": {0: "batch"},
        },
    )

    size_mb = Path(output_path).stat().st_size / 1024 / 1024
    print(f"  저장: {output_path} ({size_mb:.2f} MB)")

    return output_path


def quantize_onnx(input_path: str, output_path: str):
    """ONNX 동적 양자화 (INT8)"""
    from onnxruntime.quantization import quantize_dynamic, QuantType

    print(f"\nINT8 양자화 중...")
    quantize_dynamic(
        input_path,
        output_path,
        weight_type=QuantType.QUInt8,
    )

    original_size = Path(input_path).stat().st_size / 1024 / 1024
    quantized_size = Path(output_path).stat().st_size / 1024 / 1024
    ratio = quantized_size / original_size * 100

    print(f"  원본: {original_size:.2f} MB")
    print(f"  양자화: {quantized_size:.2f} MB ({ratio:.0f}%)")

    return output_path


def validate_onnx(model, onnx_path: str, device: str = "cpu", n_tests: int = 10):
    """ONNX와 PyTorch 출력 비교 검증"""
    print(f"\nONNX 검증 중 ({n_tests}회)...")
    sess = ort.InferenceSession(onnx_path)
    model = model.to(device).eval()

    max_diff_pts = 0
    max_diff_obj = 0

    for i in range(n_tests):
        test_in = np.random.randn(1, 3, 256, 256).astype(np.float32)
        onnx_out = sess.run(None, {"img": test_in})

        with torch.no_grad():
            torch_out = model(torch.from_numpy(test_in).to(device))

        diff_pts = np.abs(onnx_out[0] - torch_out[0].cpu().numpy()).max()
        diff_obj = np.abs(onnx_out[1] - torch_out[1].cpu().numpy()).max()
        max_diff_pts = max(max_diff_pts, diff_pts)
        max_diff_obj = max(max_diff_obj, diff_obj)

    print(f"  Points 최대 차이: {max_diff_pts:.8f}")
    print(f"  Has_obj 최대 차이: {max_diff_obj:.8f}")

    if max_diff_pts < 0.001 and max_diff_obj < 0.001:
        print(f"  검증 통과! OK")
    else:
        print(f"  [경고] 차이가 큽니다. 확인 필요")


def benchmark_onnx(onnx_path: str, n_runs: int = 100):
    """ONNX Runtime 추론 속도 벤치마크"""
    import time

    print(f"\n추론 속도 벤치마크 ({n_runs}회)...")
    sess = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    test_in = np.random.randn(1, 3, 256, 256).astype(np.float32)

    # 워밍업
    for _ in range(10):
        sess.run(None, {"img": test_in})

    # 벤치마크
    start = time.time()
    for _ in range(n_runs):
        sess.run(None, {"img": test_in})
    elapsed = (time.time() - start) / n_runs * 1000

    print(f"  평균 추론 시간 (CPU): {elapsed:.2f} ms/image")
    print(f"  FPS: {1000/elapsed:.1f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ONNX Export + Quantization")
    parser.add_argument("--model", type=str,
                        default="assets/models/lcnet050_p_multi_decoder_l3_d64_256_fp32.onnx",
                        help="원본 ONNX 모델 경로")
    parser.add_argument("--checkpoint", type=str, required=True,
                        help="학습된 체크포인트 경로")
    parser.add_argument("--output", type=str, default=None,
                        help="출력 ONNX 경로 (미지정시 자동)")
    parser.add_argument("--quantize", action="store_true",
                        help="INT8 양자화 수행")
    parser.add_argument("--benchmark", action="store_true",
                        help="추론 속도 벤치마크")
    args = parser.parse_args()

    # 출력 경로
    if args.output is None:
        ckpt_dir = Path(args.checkpoint).parent
        args.output = str(ckpt_dir / "doc_aligner_finetuned.onnx")

    # 모델 로드
    model = load_model(args.model, args.checkpoint)

    # ONNX export
    onnx_path = export_onnx(model, args.output)
    validate_onnx(model, onnx_path)

    if args.benchmark:
        benchmark_onnx(onnx_path)

    # 양자화
    if args.quantize:
        quant_path = args.output.replace(".onnx", "_int8.onnx")
        quantize_onnx(onnx_path, quant_path)
        if args.benchmark:
            benchmark_onnx(quant_path)

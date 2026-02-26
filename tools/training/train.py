"""
DocAligner Fine-tuning 학습 파이프라인
=====================================
기존 DocAligner ONNX 모델을 합성 데이터로 fine-tuning하여
책 페이지 코너 감지 성능을 향상시킵니다.

사용법:
    python train.py --data dataset --epochs 50 --batch-size 64
    python train.py --data dataset --epochs 50 --stage 1  # Stage 1만 (헤드 학습)
    python train.py --data dataset --epochs 50 --stage 2  # Stage 2만 (백본+헤드)
    python train.py --data dataset --resume checkpoint_best.pt  # 이어서 학습
"""

import argparse
import json
import time
from pathlib import Path

import cv2
import numpy as np
import onnx
import torch
import torch.nn as nn
from onnx2torch import convert
from torch.utils.data import Dataset, DataLoader


# ========== Dataset ==========

class CornerDataset(Dataset):
    """코너 감지 학습 데이터셋"""

    def __init__(self, image_dir: str, label_dir: str, indices: list, augment: bool = False):
        self.image_dir = Path(image_dir)
        self.label_dir = Path(label_dir)
        self.indices = indices
        self.augment = augment

    def __len__(self):
        return len(self.indices)

    def __getitem__(self, idx):
        i = self.indices[idx]
        img_path = self.image_dir / f"{i:05d}.jpg"
        label_path = self.label_dir / f"{i:05d}.npy"

        # 이미지 로드 + 전처리
        img = cv2.imread(str(img_path))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = img.astype(np.float32) / 255.0  # [0, 1] 정규화

        # 온라인 증강 (학습 시)
        if self.augment:
            img = self._augment(img)

        # CHW 변환
        img = torch.from_numpy(img).permute(2, 0, 1)  # [3, 256, 256]

        # 라벨 로드
        label = np.load(str(label_path)).astype(np.float32)

        # has_obj: 코너 합이 0이면 문서 없음
        has_obj = 1.0 if label.sum() > 0 else 0.0

        return img, torch.from_numpy(label), torch.tensor([has_obj])

    def _augment(self, img: np.ndarray) -> np.ndarray:
        """경량 온라인 증강 (좌우 반전, 색상 지터)"""
        # 색상 지터
        if np.random.random() < 0.3:
            jitter = np.random.uniform(0.95, 1.05, 3).astype(np.float32)
            img = np.clip(img * jitter[np.newaxis, np.newaxis, :], 0, 1)

        # 밝기 지터
        if np.random.random() < 0.3:
            img = np.clip(img * np.random.uniform(0.85, 1.15), 0, 1)

        return img.astype(np.float32)


# ========== Loss ==========

class CornerLoss(nn.Module):
    """
    코너 좌표 회귀 + 문서 존재 분류 결합 손실
    - points_loss: SmoothL1 (문서가 있는 샘플만)
    - has_obj_loss: BCE (모든 샘플)
    - area_reg: 면적 정규화 (사각형 뒤집힘 방지)
    """

    def __init__(self, points_weight=1.0, obj_weight=0.5, area_weight=0.1):
        super().__init__()
        self.smooth_l1 = nn.SmoothL1Loss(reduction="none")
        self.bce = nn.BCELoss()
        self.points_weight = points_weight
        self.obj_weight = obj_weight
        self.area_weight = area_weight

    def forward(self, pred_points, pred_obj, gt_points, gt_obj):
        # has_obj 손실 (모든 샘플)
        obj_loss = self.bce(pred_obj, gt_obj)

        # points 손실 (문서가 있는 샘플만)
        mask = gt_obj.squeeze(-1) > 0.5  # [B]
        if mask.sum() > 0:
            pred_pts = pred_points[mask]  # [N, 8]
            gt_pts = gt_points[mask]  # [N, 8]
            pts_loss = self.smooth_l1(pred_pts, gt_pts).mean()

            # 면적 정규화
            area_loss = self._area_regularization(pred_pts)
        else:
            pts_loss = torch.tensor(0.0, device=pred_points.device)
            area_loss = torch.tensor(0.0, device=pred_points.device)

        total = (self.points_weight * pts_loss +
                 self.obj_weight * obj_loss +
                 self.area_weight * area_loss)

        return total, {
            "total": total.item(),
            "points": pts_loss.item(),
            "obj": obj_loss.item(),
            "area": area_loss.item(),
        }

    def _area_regularization(self, pred_pts):
        """Shoelace formula — 면적이 너무 작으면 페널티"""
        corners = pred_pts.view(-1, 4, 2)
        x = corners[:, :, 0]
        y = corners[:, :, 1]
        n = 4
        area = torch.zeros(corners.shape[0], device=corners.device)
        for i in range(n):
            j = (i + 1) % n
            area += x[:, i] * y[:, j] - x[:, j] * y[:, i]
        area = torch.abs(area) / 2

        # 최소 면적 10% (256×256의 10% = 0.1 정규화 기준)
        penalty = torch.relu(0.05 - area).mean()
        return penalty


# ========== Evaluation ==========

def evaluate(model, dataloader, device, criterion):
    """검증 데이터셋 평가"""
    model.eval()
    total_loss = 0
    total_pts_loss = 0
    total_count = 0
    corner_dists = []

    with torch.no_grad():
        for imgs, gt_pts, gt_obj in dataloader:
            imgs = imgs.to(device)
            gt_pts = gt_pts.to(device)
            gt_obj = gt_obj.to(device)

            outputs = model(imgs)
            pred_pts = outputs[0]
            pred_obj = torch.sigmoid(outputs[1])

            loss, loss_dict = criterion(pred_pts, pred_obj, gt_pts, gt_obj)
            total_loss += loss.item() * imgs.size(0)
            total_pts_loss += loss_dict["points"] * imgs.size(0)
            total_count += imgs.size(0)

            # 코너 거리 계산 (문서 있는 샘플만)
            mask = gt_obj.squeeze(-1) > 0.5
            if mask.sum() > 0:
                pred_corners = pred_pts[mask].view(-1, 4, 2).cpu().numpy()
                gt_corners = gt_pts[mask].view(-1, 4, 2).cpu().numpy()
                dists = np.linalg.norm(pred_corners - gt_corners, axis=-1) * 256  # 픽셀 단위
                corner_dists.extend(dists.mean(axis=1).tolist())

    avg_loss = total_loss / max(total_count, 1)
    avg_pts = total_pts_loss / max(total_count, 1)
    avg_dist = np.mean(corner_dists) if corner_dists else 0
    success_rate = np.mean([d < 10 for d in corner_dists]) if corner_dists else 0

    return {
        "loss": avg_loss,
        "pts_loss": avg_pts,
        "avg_corner_dist_px": avg_dist,
        "success_rate_10px": success_rate,
    }


# ========== Training ==========

def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    import sys
    # stdout 버퍼링 비활성화
    sys.stdout.reconfigure(line_buffering=True) if hasattr(sys.stdout, 'reconfigure') else None

    print(f"=== DocAligner Fine-tuning ===")
    print(f"  Device: {device}")
    if torch.cuda.is_available():
        print(f"  GPU: {torch.cuda.get_device_name(0)}")
        print(f"  VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")

    # 데이터 로드
    data_path = Path(args.data)
    splits = json.loads((data_path / "splits.json").read_text())

    train_ds = CornerDataset(data_path / "images", data_path / "labels", splits["train"], augment=True)
    val_ds = CornerDataset(data_path / "images", data_path / "labels", splits["val"], augment=False)
    test_ds = CornerDataset(data_path / "images", data_path / "labels", splits["test"], augment=False)

    # onnx2torch 모델은 batch=1만 지원 (Reshape 하드코딩)
    # gradient accumulation으로 실질적 배치 효과 달성
    actual_batch = 1
    accum_steps = args.batch_size  # 예: 64 → 64번 누적 후 step

    train_dl = DataLoader(train_ds, batch_size=actual_batch, shuffle=True,
                          num_workers=0, pin_memory=True, drop_last=True)
    val_dl = DataLoader(val_ds, batch_size=actual_batch, shuffle=False,
                        num_workers=0, pin_memory=True)
    test_dl = DataLoader(test_ds, batch_size=actual_batch, shuffle=False,
                         num_workers=0, pin_memory=True)

    print(f"  Train: {len(train_ds)}, Val: {len(val_ds)}, Test: {len(test_ds)}")
    print(f"  Effective batch size: {args.batch_size} (accum {accum_steps} steps)")
    print(f"  Note: onnx2torch 모델은 batch=1 제한, gradient accumulation 사용")

    # 모델 로드
    print(f"\n모델 로드 중...")
    onnx_model = onnx.load(args.model)
    model = convert(onnx_model).to(device)

    total_params = sum(p.numel() for p in model.parameters())
    print(f"  총 파라미터: {total_params:,}")

    # Stage 설정
    stage = args.stage
    if stage == 1:
        _freeze_backbone(model)
    elif stage == 2:
        _unfreeze_last_blocks(model)
    else:
        # 자동: epoch 1~20은 Stage 1, 21~은 Stage 2
        _freeze_backbone(model)

    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"  학습 가능 파라미터: {trainable:,} ({trainable/total_params*100:.1f}%)")

    # 옵티마이저 + 스케줄러
    optimizer = torch.optim.AdamW(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=args.lr,
        weight_decay=args.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=args.epochs, eta_min=args.lr * 0.01
    )

    criterion = CornerLoss(points_weight=1.0, obj_weight=0.5, area_weight=0.1)

    # 체크포인트 로드
    start_epoch = 0
    best_val_dist = float("inf")
    if args.resume:
        ckpt = torch.load(weights_only=False, f=args.resume, map_location=device)
        model.load_state_dict(ckpt["model"])
        prev_stage = ckpt.get("args", {}).get("stage", None)
        # Stage가 변경된 경우 optimizer 재생성 + epoch 리셋
        if prev_stage is not None and prev_stage != stage:
            print(f"  Stage 변경 감지: {prev_stage} -> {stage}, optimizer 재생성, epoch 리셋")
            optimizer = torch.optim.AdamW(
                filter(lambda p: p.requires_grad, model.parameters()),
                lr=args.lr,
                weight_decay=args.weight_decay,
            )
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
                optimizer, T_max=args.epochs, eta_min=args.lr * 0.01
            )
            start_epoch = 0  # 새 Stage는 epoch 0부터
        else:
            optimizer.load_state_dict(ckpt["optimizer"])
            start_epoch = ckpt["epoch"] + 1
            # 스케줄러를 start_epoch 위치까지 진행
            for _ in range(start_epoch):
                scheduler.step()
        best_val_dist = ckpt.get("best_val_dist", float("inf"))
        print(f"  체크포인트 로드: epoch {start_epoch}, best_dist={best_val_dist:.2f}px")

    # 학습 루프
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    history = []

    print(f"\n학습 시작 (epochs: {args.epochs}, lr: {args.lr})")
    print("-" * 80)

    start_time = time.time()
    stage_switched = False

    for epoch in range(start_epoch, args.epochs):
        # Stage 자동 전환 (stage=0일 때)
        if stage == 0 and epoch == 20 and not stage_switched:
            print(f"\n>>> Stage 2로 전환: 마지막 3 블록 + 전체 헤드 학습 <<<")
            _unfreeze_last_blocks(model)
            # 옵티마이저 재생성 (새 파라미터 포함)
            optimizer = torch.optim.AdamW(
                filter(lambda p: p.requires_grad, model.parameters()),
                lr=args.lr * 0.1,  # Stage 2는 더 작은 LR
                weight_decay=args.weight_decay,
            )
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
                optimizer, T_max=args.epochs - 20, eta_min=args.lr * 0.001
            )
            trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
            print(f"  학습 가능 파라미터: {trainable:,}")
            stage_switched = True

        epoch_start = time.time()
        model.train()
        epoch_loss = 0
        epoch_pts = 0
        batch_count = 0
        optimizer.zero_grad()

        for step, (imgs, gt_pts, gt_obj) in enumerate(train_dl):
            imgs = imgs.to(device)
            gt_pts = gt_pts.to(device)
            gt_obj = gt_obj.to(device)

            outputs = model(imgs)
            pred_pts = outputs[0]
            pred_obj = torch.sigmoid(outputs[1])

            loss, loss_dict = criterion(pred_pts, pred_obj, gt_pts, gt_obj)
            loss = loss / accum_steps  # gradient accumulation 스케일링
            loss.backward()

            epoch_loss += loss_dict["total"]
            epoch_pts += loss_dict["points"]

            # accum_steps마다 파라미터 업데이트
            if (step + 1) % accum_steps == 0:
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
                optimizer.step()
                optimizer.zero_grad()
                batch_count += 1

        # 남은 gradient 처리
        if (step + 1) % accum_steps != 0:
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()
            optimizer.zero_grad()
            batch_count += 1

        scheduler.step()

        total_steps = step + 1
        avg_train_loss = epoch_loss / max(total_steps, 1)
        avg_train_pts = epoch_pts / max(total_steps, 1)

        epoch_time = time.time() - epoch_start

        # 검증 (5에폭마다 또는 마지막)
        if (epoch + 1) % 5 == 0 or epoch == args.epochs - 1:
            val_metrics = evaluate(model, val_dl, device, criterion)
            val_dist = val_metrics["avg_corner_dist_px"]
            val_success = val_metrics["success_rate_10px"]

            improved = ""
            if val_dist < best_val_dist:
                best_val_dist = val_dist
                improved = " * BEST"
                # 베스트 모델 저장
                torch.save({
                    "epoch": epoch,
                    "model": model.state_dict(),
                    "optimizer": optimizer.state_dict(),
                    "best_val_dist": best_val_dist,
                    "args": vars(args),
                }, output_dir / "checkpoint_best.pt")

            lr = optimizer.param_groups[0]["lr"]
            print(f"  Epoch {epoch+1:3d}/{args.epochs} [{epoch_time:.0f}s] | "
                  f"loss={avg_train_loss:.4f} pts={avg_train_pts:.4f} | "
                  f"val_dist={val_dist:.1f}px ok={val_success:.0%} | "
                  f"lr={lr:.6f}{improved}")

            history.append({
                "epoch": epoch + 1,
                "train_loss": avg_train_loss,
                "train_pts": avg_train_pts,
                "val_loss": val_metrics["loss"],
                "val_dist": val_dist,
                "val_success": val_success,
                "lr": lr,
            })
        else:
            lr = optimizer.param_groups[0]["lr"]
            print(f"  Epoch {epoch+1:3d}/{args.epochs} [{epoch_time:.0f}s] | "
                  f"loss={avg_train_loss:.4f} pts={avg_train_pts:.4f} | "
                  f"lr={lr:.6f}")

    elapsed = time.time() - start_time
    print(f"\n학습 완료! (총 {elapsed:.1f}초 = {elapsed/60:.1f}분)")
    print(f"  Best val dist: {best_val_dist:.2f}px")

    # 마지막 체크포인트 저장
    torch.save({
        "epoch": args.epochs - 1,
        "model": model.state_dict(),
        "optimizer": optimizer.state_dict(),
        "best_val_dist": best_val_dist,
        "args": vars(args),
    }, output_dir / "checkpoint_last.pt")

    # 테스트 평가
    print(f"\n=== 테스트 평가 ===")
    # 베스트 모델 로드
    ckpt = torch.load(weights_only=False, f=output_dir / "checkpoint_best.pt", map_location=device)
    model.load_state_dict(ckpt["model"])
    test_metrics = evaluate(model, test_dl, device, criterion)
    print(f"  Test loss: {test_metrics['loss']:.4f}")
    print(f"  Test avg corner dist: {test_metrics['avg_corner_dist_px']:.2f}px")
    print(f"  Test success rate (10px): {test_metrics['success_rate_10px']:.1%}")

    # 히스토리 저장
    with open(output_dir / "training_history.json", "w") as f:
        json.dump({
            "args": vars(args),
            "elapsed_seconds": elapsed,
            "best_val_dist": best_val_dist,
            "test_metrics": test_metrics,
            "history": history,
        }, f, indent=2)

    print(f"\n  체크포인트: {output_dir / 'checkpoint_best.pt'}")
    print(f"  히스토리: {output_dir / 'training_history.json'}")

    return model, output_dir


# ========== Freeze/Unfreeze 전략 ==========

def _freeze_backbone(model):
    """Stage 1: 전체 backbone 동결, head만 학습"""
    for name, param in model.named_parameters():
        if "backbone" in name:
            param.requires_grad = False
        else:
            param.requires_grad = True
    print("  [Stage 1] Backbone 동결, Head만 학습")


def _unfreeze_last_blocks(model):
    """Stage 2: backbone 마지막 3블록(3,4,5) + 전체 head 학습"""
    for name, param in model.named_parameters():
        param.requires_grad = False  # 일단 전체 동결

    for name, param in model.named_parameters():
        # head 전체 학습
        if "head" in name:
            param.requires_grad = True
        # backbone blocks/3, 4, 5 학습
        if any(f"blocks/{i}" in name or f"blocks\\{i}" in name
               for i in [3, 4, 5]):
            param.requires_grad = True

    print("  [Stage 2] Backbone blocks/3~5 + 전체 Head 학습")


# ========== ONNX Export ==========

def export_onnx(model, output_path: str, device="cpu"):
    """PyTorch 모델 → ONNX 변환"""
    model = model.to(device).eval()
    dummy = torch.randn(1, 3, 256, 256, device=device)

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

    # 검증
    import onnxruntime as ort
    sess = ort.InferenceSession(output_path)
    test_in = np.random.randn(1, 3, 256, 256).astype(np.float32)
    onnx_out = sess.run(None, {"img": test_in})

    with torch.no_grad():
        torch_out = model(torch.from_numpy(test_in).to(device))

    diff_pts = np.abs(onnx_out[0] - torch_out[0].cpu().numpy()).max()
    diff_obj = np.abs(onnx_out[1] - torch_out[1].cpu().numpy()).max()

    size_mb = Path(output_path).stat().st_size / 1024 / 1024
    print(f"  ONNX 저장: {output_path} ({size_mb:.2f} MB)")
    print(f"  Points 차이: {diff_pts:.8f}")
    print(f"  Has_obj 차이: {diff_obj:.8f}")

    return output_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DocAligner Fine-tuning")
    parser.add_argument("--model", type=str,
                        default="assets/models/lcnet050_p_multi_decoder_l3_d64_256_fp32.onnx",
                        help="원본 ONNX 모델 경로")
    parser.add_argument("--data", type=str, default="tools/training/dataset",
                        help="학습 데이터셋 경로")
    parser.add_argument("--output", type=str, default="tools/training/checkpoints",
                        help="체크포인트 출력 경로")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-5)
    parser.add_argument("--stage", type=int, default=0,
                        help="0=자동(1→2전환), 1=헤드만, 2=백본+헤드")
    parser.add_argument("--resume", type=str, default=None,
                        help="체크포인트에서 이어서 학습")
    parser.add_argument("--export-onnx", action="store_true",
                        help="학습 후 ONNX 변환")
    args = parser.parse_args()

    model, output_dir = train(args)

    if args.export_onnx:
        print(f"\n=== ONNX 변환 ===")
        onnx_path = str(output_dir / "doc_aligner_finetuned.onnx")
        export_onnx(model, onnx_path)

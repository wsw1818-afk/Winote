"""
합성 문서/책 코너 감지 학습 데이터 생성기
=============================================
문서/책 이미지를 배경 위에 랜덤 원근 변환하여 합성 데이터를 생성합니다.
코너 좌표가 자동으로 ground truth가 되므로 수동 라벨링이 불필요합니다.

사용법:
    python generate_synthetic_data.py --count 5000 --output dataset
    python generate_synthetic_data.py --count 100 --output dataset --visualize  # 시각화 포함
"""

import cv2
import numpy as np
import random
import argparse
import json
import os
from pathlib import Path
from typing import Tuple, List, Optional


class SyntheticDocumentGenerator:
    """합성 문서/책 코너 감지 학습 데이터 생성기"""

    def __init__(
        self,
        doc_dir: Optional[str] = None,
        bg_dir: Optional[str] = None,
        output_size: int = 256,
    ):
        self.output_size = output_size
        self.documents = []
        self.backgrounds = []

        # 외부 문서 이미지 로드
        if doc_dir and Path(doc_dir).exists():
            for ext in ("*.jpg", "*.png", "*.jpeg", "*.bmp"):
                self.documents.extend(Path(doc_dir).glob(ext))
            print(f"  외부 문서 이미지: {len(self.documents)}장 로드")

        # 외부 배경 이미지 로드
        if bg_dir and Path(bg_dir).exists():
            for ext in ("*.jpg", "*.png", "*.jpeg", "*.bmp"):
                self.backgrounds.extend(Path(bg_dir).glob(ext))
            print(f"  외부 배경 이미지: {len(self.backgrounds)}장 로드")

    # ========== 문서/배경 자체 생성 ==========

    def _generate_document(self) -> np.ndarray:
        """프로그래밍으로 문서 이미지 생성 (텍스트 + 레이아웃)"""
        h, w = random.choice([(400, 300), (500, 350), (600, 420), (700, 500), (800, 560)])
        doc_type = random.choice(["text", "book", "receipt", "card", "table"])

        # 기본 배경색 (종이 느낌)
        base_color = random.randint(230, 255)
        variation = random.randint(0, 10)
        bg = np.full((h, w, 3), [base_color - variation, base_color, base_color + variation // 2], dtype=np.uint8)

        # 약간의 질감 노이즈
        noise = np.random.normal(0, random.uniform(1, 4), (h, w, 3)).astype(np.float32)
        bg = np.clip(bg.astype(np.float32) + noise, 0, 255).astype(np.uint8)

        if doc_type == "text":
            self._draw_text_lines(bg, h, w)
        elif doc_type == "book":
            self._draw_book_page(bg, h, w)
        elif doc_type == "receipt":
            self._draw_receipt(bg, h, w)
        elif doc_type == "card":
            self._draw_card(bg, h, w)
        elif doc_type == "table":
            self._draw_table(bg, h, w)

        return bg

    def _draw_text_lines(self, img, h, w):
        """텍스트 줄 그리기 (문서)"""
        margin_x = int(w * 0.08)
        margin_y = int(h * 0.06)
        line_height = random.randint(12, 20)
        text_color = random.randint(10, 60)

        # 제목
        y = margin_y + 20
        title_w = random.randint(int(w * 0.3), int(w * 0.7))
        cv2.rectangle(img, (margin_x, y), (margin_x + title_w, y + line_height + 4),
                      (text_color, text_color, text_color), -1)
        y += line_height + 20

        # 본문 줄
        while y < h - margin_y - line_height:
            line_w = random.randint(int(w * 0.6), w - margin_x * 2)
            thickness = random.choice([1, 2])
            # 일부 줄은 단락 나눔
            if random.random() < 0.1:
                y += line_height
                continue
            # 일부 줄은 들여쓰기
            indent = random.choice([0, 0, 0, int(w * 0.05)])
            cv2.rectangle(img, (margin_x + indent, y), (margin_x + indent + line_w, y + thickness + 2),
                          (text_color, text_color, text_color + 10), -1)
            y += line_height

    def _draw_book_page(self, img, h, w):
        """책 페이지 레이아웃"""
        margin_x = int(w * 0.1)
        margin_y = int(h * 0.08)
        text_color = random.randint(15, 55)
        line_height = random.randint(10, 16)

        # 페이지 번호 (하단)
        pg_num_x = random.choice([margin_x, w - margin_x - 20])
        cv2.rectangle(img, (pg_num_x, h - margin_y), (pg_num_x + 15, h - margin_y + 8),
                      (text_color, text_color, text_color), -1)

        # 중앙 접힘 효과 (약간 어두운 세로 줄)
        if random.random() < 0.5:
            side = random.choice(["left", "right"])
            if side == "left":
                for dx in range(8):
                    x = dx
                    factor = 0.85 + 0.15 * (dx / 8)
                    img[:, x] = np.clip(img[:, x] * factor, 0, 255).astype(np.uint8)
            else:
                for dx in range(8):
                    x = w - 1 - dx
                    factor = 0.85 + 0.15 * (dx / 8)
                    img[:, x] = np.clip(img[:, x] * factor, 0, 255).astype(np.uint8)

        # 본문
        y = margin_y + 10
        while y < h - margin_y - line_height:
            line_w = random.randint(int(w * 0.65), w - margin_x * 2)
            cv2.rectangle(img, (margin_x, y), (margin_x + line_w, y + 2),
                          (text_color, text_color, text_color), -1)
            y += line_height
            if random.random() < 0.05:  # 단락 간격
                y += line_height

        # 가끔 삽화/이미지 영역
        if random.random() < 0.3:
            ix = random.randint(margin_x, w - margin_x - 80)
            iy = random.randint(margin_y + 40, h - margin_y - 80)
            iw = random.randint(60, min(120, w - ix - margin_x))
            ih = random.randint(50, min(100, h - iy - margin_y))
            cv2.rectangle(img, (ix, iy), (ix + iw, iy + ih),
                          (text_color + 30, text_color + 30, text_color + 30), 2)
            # 내부 대각선 (이미지 플레이스홀더)
            cv2.line(img, (ix, iy), (ix + iw, iy + ih), (text_color + 50, text_color + 50, text_color + 50), 1)

    def _draw_receipt(self, img, h, w):
        """영수증 레이아웃"""
        margin_x = int(w * 0.06)
        text_color = random.randint(20, 70)
        y = 15

        # 상호명 (굵은 줄)
        center_x = w // 2
        cv2.rectangle(img, (center_x - 40, y), (center_x + 40, y + 10), (text_color, text_color, text_color), -1)
        y += 25

        # 구분선
        cv2.line(img, (margin_x, y), (w - margin_x, y), (text_color + 40, text_color + 40, text_color + 40), 1)
        y += 15

        # 항목들
        while y < h - 40:
            # 항목명
            item_w = random.randint(30, int(w * 0.4))
            cv2.rectangle(img, (margin_x, y), (margin_x + item_w, y + 2), (text_color, text_color, text_color), -1)
            # 금액 (오른쪽 정렬)
            price_w = random.randint(20, 40)
            cv2.rectangle(img, (w - margin_x - price_w, y), (w - margin_x, y + 2), (text_color, text_color, text_color), -1)
            y += random.randint(10, 16)

            if random.random() < 0.15:  # 구분선
                cv2.line(img, (margin_x, y), (w - margin_x, y), (text_color + 60, text_color + 60, text_color + 60), 1)
                y += 8

    def _draw_card(self, img, h, w):
        """명함/카드 레이아웃"""
        text_color = random.randint(20, 80)
        # 로고 영역
        cv2.rectangle(img, (20, 15), (60, 40), (text_color, text_color + 20, text_color + 40), -1)
        # 이름
        cv2.rectangle(img, (20, 55), (w // 2, 65), (text_color, text_color, text_color), -1)
        # 직함
        cv2.rectangle(img, (20, 75), (w // 3, 82), (text_color + 30, text_color + 30, text_color + 30), -1)
        # 연락처
        for i, y in enumerate([h - 60, h - 45, h - 30]):
            line_w = random.randint(60, w - 40)
            cv2.rectangle(img, (20, y), (20 + line_w, y + 2), (text_color + 20, text_color + 20, text_color + 20), -1)

    def _draw_table(self, img, h, w):
        """표 형식 문서"""
        margin = int(min(h, w) * 0.08)
        text_color = random.randint(20, 60)
        rows = random.randint(5, 12)
        cols = random.randint(2, 5)

        table_w = w - margin * 2
        table_h = h - margin * 2
        cell_w = table_w // cols
        cell_h = table_h // rows

        # 격자 그리기
        for r in range(rows + 1):
            y = margin + r * cell_h
            cv2.line(img, (margin, y), (margin + table_w, y), (text_color + 40, text_color + 40, text_color + 40), 1)
        for c in range(cols + 1):
            x = margin + c * cell_w
            cv2.line(img, (x, margin), (x, margin + table_h), (text_color + 40, text_color + 40, text_color + 40), 1)

        # 셀 내용
        for r in range(rows):
            for c in range(cols):
                if random.random() < 0.8:
                    cx = margin + c * cell_w + 5
                    cy = margin + r * cell_h + cell_h // 2 - 1
                    tw = random.randint(10, cell_w - 10)
                    cv2.rectangle(img, (cx, cy), (cx + tw, cy + 2), (text_color, text_color, text_color), -1)

    def _generate_background(self) -> np.ndarray:
        """프로그래밍으로 배경 이미지 생성"""
        size = self.output_size
        bg_type = random.choice(["solid", "gradient", "noise_texture", "wood", "fabric", "desk"])

        if bg_type == "solid":
            color = [random.randint(30, 220) for _ in range(3)]
            bg = np.full((size, size, 3), color, dtype=np.uint8)
            noise = np.random.normal(0, random.uniform(2, 8), (size, size, 3))
            bg = np.clip(bg.astype(np.float32) + noise, 0, 255).astype(np.uint8)

        elif bg_type == "gradient":
            bg = np.zeros((size, size, 3), dtype=np.uint8)
            c1 = np.array([random.randint(20, 200) for _ in range(3)])
            c2 = np.array([random.randint(20, 200) for _ in range(3)])
            angle = random.choice(["vertical", "horizontal", "diagonal"])
            for y in range(size):
                for x in range(size):
                    if angle == "vertical":
                        t = y / size
                    elif angle == "horizontal":
                        t = x / size
                    else:
                        t = (x + y) / (2 * size)
                    bg[y, x] = np.clip(c1 * (1 - t) + c2 * t, 0, 255).astype(np.uint8)

        elif bg_type == "noise_texture":
            base = random.randint(60, 180)
            bg = np.random.normal(base, random.uniform(10, 30), (size, size, 3))
            bg = np.clip(bg, 0, 255).astype(np.uint8)
            bg = cv2.GaussianBlur(bg, (5, 5), 0)

        elif bg_type == "wood":
            bg = np.zeros((size, size, 3), dtype=np.uint8)
            base_color = np.array([random.randint(40, 80), random.randint(80, 140), random.randint(140, 200)])
            for y in range(size):
                stripe = np.sin(y * random.uniform(0.05, 0.15)) * 20
                bg[y, :] = np.clip(base_color + stripe, 0, 255).astype(np.uint8)
            noise = np.random.normal(0, 5, (size, size, 3))
            bg = np.clip(bg.astype(np.float32) + noise, 0, 255).astype(np.uint8)

        elif bg_type == "fabric":
            bg = np.zeros((size, size, 3), dtype=np.uint8)
            base = np.array([random.randint(40, 180) for _ in range(3)])
            bg[:] = base
            # 직물 패턴
            for y in range(0, size, random.randint(3, 6)):
                cv2.line(bg, (0, y), (size, y), tuple(int(c) for c in np.clip(base - 15, 0, 255)), 1)
            for x in range(0, size, random.randint(3, 6)):
                cv2.line(bg, (x, 0), (x, size), tuple(int(c) for c in np.clip(base - 10, 0, 255)), 1)
            noise = np.random.normal(0, 3, (size, size, 3))
            bg = np.clip(bg.astype(np.float32) + noise, 0, 255).astype(np.uint8)

        else:  # desk
            base = random.randint(100, 200)
            bg = np.full((size, size, 3), [base - 20, base - 5, base + 10], dtype=np.uint8)
            # 임의의 작은 물체/그림자
            for _ in range(random.randint(0, 3)):
                cx, cy = random.randint(20, size - 20), random.randint(20, size - 20)
                rw, rh = random.randint(10, 40), random.randint(10, 40)
                color = [random.randint(40, 180) for _ in range(3)]
                cv2.rectangle(bg, (cx, cy), (cx + rw, cy + rh), color, -1)
            bg = cv2.GaussianBlur(bg, (3, 3), 0)

        return bg

    # ========== 핵심 합성 로직 ==========

    def _get_document_image(self) -> np.ndarray:
        """문서 이미지 가져오기 (외부 파일 또는 자체 생성)"""
        if self.documents and random.random() < 0.4:
            path = random.choice(self.documents)
            img = cv2.imread(str(path))
            if img is not None:
                return img
        return self._generate_document()

    def _get_background_image(self) -> np.ndarray:
        """배경 이미지 가져오기 (외부 파일 또는 자체 생성)"""
        if self.backgrounds and random.random() < 0.4:
            path = random.choice(self.backgrounds)
            img = cv2.imread(str(path))
            if img is not None:
                return cv2.resize(img, (self.output_size, self.output_size))
        return self._generate_background()

    def _random_corners(self) -> np.ndarray:
        """랜덤 코너 좌표 생성 (원근 변환 목표)"""
        s = self.output_size
        margin = s * random.uniform(0.03, 0.12)  # 여백 3~12%

        # 문서 크기 범위: 화면의 40~90%
        doc_ratio = random.uniform(0.40, 0.90)

        # 중심점 약간 랜덤 오프셋
        cx = s / 2 + random.uniform(-s * 0.15, s * 0.15)
        cy = s / 2 + random.uniform(-s * 0.15, s * 0.15)

        half_w = s * doc_ratio / 2
        half_h = s * doc_ratio / 2 * random.uniform(0.7, 1.3)  # 가로세로 비율 변화

        # 각 코너에 랜덤 원근 왜곡 추가
        perturb = s * random.uniform(0.01, 0.08)  # 원근 왜곡 정도

        corners = np.float32([
            [cx - half_w + random.uniform(-perturb, perturb),
             cy - half_h + random.uniform(-perturb, perturb)],   # top-left
            [cx + half_w + random.uniform(-perturb, perturb),
             cy - half_h + random.uniform(-perturb, perturb)],   # top-right
            [cx + half_w + random.uniform(-perturb, perturb),
             cy + half_h + random.uniform(-perturb, perturb)],   # bottom-right
            [cx - half_w + random.uniform(-perturb, perturb),
             cy + half_h + random.uniform(-perturb, perturb)],   # bottom-left
        ])

        # 클리핑: 이미지 범위 내로
        corners = np.clip(corners, margin, s - margin)

        return corners

    def _apply_lighting(self, img: np.ndarray) -> np.ndarray:
        """랜덤 조명 변화"""
        # 밝기
        brightness = random.uniform(0.65, 1.35)
        img = np.clip(img.astype(np.float32) * brightness, 0, 255).astype(np.uint8)

        # 색온도
        if random.random() < 0.3:
            warm = random.uniform(0.92, 1.08)
            img_f = img.astype(np.float32)
            img_f[:, :, 2] = np.clip(img_f[:, :, 2] * warm, 0, 255)
            img_f[:, :, 0] = np.clip(img_f[:, :, 0] / warm, 0, 255)
            img = img_f.astype(np.uint8)

        return img

    def _apply_shadow(self, img: np.ndarray) -> np.ndarray:
        """그라디언트 그림자 효과"""
        if random.random() > 0.4:
            return img

        h, w = img.shape[:2]
        shadow = np.ones((h, w), dtype=np.float32)
        direction = random.choice(["left", "right", "top", "bottom", "radial"])
        strength = random.uniform(0.3, 0.7)

        if direction == "left":
            grad = np.linspace(strength, 1.0, w).reshape(1, w)
            shadow = np.tile(grad, (h, 1))
        elif direction == "right":
            grad = np.linspace(1.0, strength, w).reshape(1, w)
            shadow = np.tile(grad, (h, 1))
        elif direction == "top":
            grad = np.linspace(strength, 1.0, h).reshape(h, 1)
            shadow = np.tile(grad, (1, w))
        elif direction == "bottom":
            grad = np.linspace(1.0, strength, h).reshape(h, 1)
            shadow = np.tile(grad, (1, w))
        elif direction == "radial":
            cx, cy = random.randint(0, w), random.randint(0, h)
            Y, X = np.mgrid[0:h, 0:w]
            dist = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
            max_dist = np.sqrt(h ** 2 + w ** 2)
            shadow = strength + (1 - strength) * (dist / max_dist)

        shadow_3ch = np.stack([shadow] * 3, axis=-1)
        img = np.clip(img.astype(np.float32) * shadow_3ch, 0, 255).astype(np.uint8)
        return img

    def _apply_noise(self, img: np.ndarray) -> np.ndarray:
        """가우시안 노이즈"""
        if random.random() > 0.5:
            return img
        sigma = random.uniform(2, 12)
        noise = np.random.normal(0, sigma, img.shape).astype(np.float32)
        return np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)

    def _apply_blur(self, img: np.ndarray) -> np.ndarray:
        """모션/가우시안 블러"""
        if random.random() > 0.3:
            return img
        k = random.choice([3, 5])
        return cv2.GaussianBlur(img, (k, k), random.uniform(0.5, 1.5))

    def _apply_jpeg_artifact(self, img: np.ndarray) -> np.ndarray:
        """JPEG 압축 아티팩트"""
        if random.random() > 0.3:
            return img
        quality = random.randint(40, 90)
        _, encoded = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
        return cv2.imdecode(encoded, cv2.IMREAD_COLOR)

    def _apply_book_effects(self, img: np.ndarray, corners: np.ndarray) -> np.ndarray:
        """책 전용 효과 (접힘 그림자, 페이지 말림)"""
        h, w = img.shape[:2]

        # 책 접힘 그림자 (중앙 세로 어두운 줄)
        if random.random() < 0.35:
            fold_x = w // 2 + random.randint(-20, 20)
            fold_width = random.randint(5, 15)
            for dx in range(-fold_width, fold_width + 1):
                x = fold_x + dx
                if 0 <= x < w:
                    factor = 0.6 + 0.4 * abs(dx) / fold_width
                    img[:, x] = np.clip(img[:, x].astype(np.float32) * factor, 0, 255).astype(np.uint8)

        # 페이지 그림자 (한쪽 가장자리)
        if random.random() < 0.4:
            shadow_side = random.choice(["left", "right"])
            shadow_w = random.randint(3, 12)
            for dx in range(shadow_w):
                if shadow_side == "left":
                    x = dx
                else:
                    x = w - 1 - dx
                if 0 <= x < w:
                    factor = 0.65 + 0.35 * (dx / shadow_w)
                    img[:, x] = np.clip(img[:, x].astype(np.float32) * factor, 0, 255).astype(np.uint8)

        return img

    def generate_sample(self, is_book: bool = False) -> Tuple[np.ndarray, np.ndarray]:
        """
        1개의 학습 샘플 생성
        Returns: (image [256,256,3], corners [8] normalized 0~1)
        """
        # 1. 문서/배경 가져오기
        doc = self._get_document_image()
        bg = self._get_background_image()

        # 2. 랜덤 코너 좌표 생성 (ground truth)
        corners_dst = self._random_corners()

        # 3. 문서를 코너 위치로 원근 변환
        doc_h, doc_w = doc.shape[:2]
        corners_src = np.float32([
            [0, 0], [doc_w, 0], [doc_w, doc_h], [0, doc_h]
        ])
        M = cv2.getPerspectiveTransform(corners_src, corners_dst)
        warped = cv2.warpPerspective(
            doc, M, (self.output_size, self.output_size),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0),
        )

        # 4. 마스크 생성 + 배경 합성
        mask = np.zeros((self.output_size, self.output_size), dtype=np.uint8)
        cv2.fillConvexPoly(mask, corners_dst.astype(np.int32), 255)

        # 가장자리 안티앨리어싱
        mask_blur = cv2.GaussianBlur(mask, (3, 3), 0)
        mask_3ch = cv2.merge([mask_blur, mask_blur, mask_blur]).astype(np.float32) / 255.0
        result = (warped.astype(np.float32) * mask_3ch + bg.astype(np.float32) * (1 - mask_3ch))
        result = result.astype(np.uint8)

        # 5. 효과 적용
        if is_book:
            result = self._apply_book_effects(result, corners_dst)

        result = self._apply_lighting(result)
        result = self._apply_shadow(result)
        result = self._apply_noise(result)
        result = self._apply_blur(result)
        result = self._apply_jpeg_artifact(result)

        # 6. 정규화된 코너 좌표 (0~1, TL→TR→BR→BL 순서)
        normalized = corners_dst / self.output_size
        label = normalized.flatten()  # [x0,y0, x1,y1, x2,y2, x3,y3]

        return result, label

    def generate_binder_sample(self) -> Tuple[np.ndarray, np.ndarray]:
        """
        바인더 노트 합성 샘플 생성
        커버(어두운 사각형) 위에 흰 용지가 놓인 구조.
        Ground truth = 용지의 코너 (커버가 아닌 내부 용지)
        """
        s = self.output_size
        bg = self._get_background_image()

        # 1) 바인더 커버 (어두운 색 큰 사각형)
        cover_margin = s * random.uniform(0.02, 0.08)
        cover_corners = self._random_corners()
        # 커버는 화면 대부분 차지
        cx, cy = s / 2 + random.uniform(-s * 0.08, s * 0.08), s / 2 + random.uniform(-s * 0.08, s * 0.08)
        cover_half_w = s * random.uniform(0.38, 0.48)
        cover_half_h = s * random.uniform(0.35, 0.46)
        perturb = s * random.uniform(0.01, 0.04)
        cover_corners = np.float32([
            [cx - cover_half_w + random.uniform(-perturb, perturb),
             cy - cover_half_h + random.uniform(-perturb, perturb)],
            [cx + cover_half_w + random.uniform(-perturb, perturb),
             cy - cover_half_h + random.uniform(-perturb, perturb)],
            [cx + cover_half_w + random.uniform(-perturb, perturb),
             cy + cover_half_h + random.uniform(-perturb, perturb)],
            [cx - cover_half_w + random.uniform(-perturb, perturb),
             cy + cover_half_h + random.uniform(-perturb, perturb)],
        ])
        cover_corners = np.clip(cover_corners, 2, s - 2)

        # 커버 색상 (어두운 색: 검정/갈색/남색)
        cover_color_base = random.choice([
            [30, 30, 40],    # 검정
            [30, 40, 60],    # 남색
            [40, 50, 70],    # 진갈색
            [50, 50, 50],    # 진회색
            [20, 30, 50],    # 다크 블루
        ])
        cover_img = np.full((s, s, 3), cover_color_base, dtype=np.uint8)
        noise = np.random.normal(0, 3, (s, s, 3))
        cover_img = np.clip(cover_img.astype(np.float32) + noise, 0, 255).astype(np.uint8)

        # 커버를 배경에 합성
        mask_cover = np.zeros((s, s), dtype=np.uint8)
        cv2.fillConvexPoly(mask_cover, cover_corners.astype(np.int32), 255)
        mask_cover_3ch = cv2.merge([mask_cover] * 3).astype(np.float32) / 255.0
        result = (cover_img.astype(np.float32) * mask_cover_3ch +
                  bg.astype(np.float32) * (1 - mask_cover_3ch)).astype(np.uint8)

        # 2) 바인더 링 (왼쪽 또는 오른쪽에 원형 링)
        ring_side = random.choice(["left", "right"])
        n_rings = random.randint(4, 7)
        cover_top = int(min(cover_corners[0][1], cover_corners[1][1]))
        cover_bot = int(max(cover_corners[2][1], cover_corners[3][1]))
        if ring_side == "left":
            ring_x = int(min(cover_corners[0][0], cover_corners[3][0])) + random.randint(5, 15)
        else:
            ring_x = int(max(cover_corners[1][0], cover_corners[2][0])) - random.randint(5, 15)

        ring_spacing = (cover_bot - cover_top) / (n_rings + 1)
        ring_color = random.choice([(180, 180, 190), (160, 160, 170), (200, 200, 210)])
        ring_r = random.randint(4, 8)
        for ri in range(n_rings):
            ry = int(cover_top + ring_spacing * (ri + 1))
            cv2.circle(result, (ring_x, ry), ring_r, ring_color, 2)
            # 링 내부 (배경색 보임)
            cv2.circle(result, (ring_x, ry), ring_r - 2, tuple(cover_color_base), -1)

        # 3) 용지 (흰색, 커버보다 안쪽) — 이것이 ground truth
        # 용지는 커버보다 약간 안쪽에 위치
        inset = s * random.uniform(0.02, 0.06)
        # 링 쪽은 더 많이 안쪽으로
        ring_inset = s * random.uniform(0.04, 0.10)

        if ring_side == "left":
            paper_corners = np.float32([
                [cover_corners[0][0] + ring_inset + random.uniform(-3, 3),
                 cover_corners[0][1] + inset + random.uniform(-3, 3)],
                [cover_corners[1][0] - inset + random.uniform(-3, 3),
                 cover_corners[1][1] + inset + random.uniform(-3, 3)],
                [cover_corners[2][0] - inset + random.uniform(-3, 3),
                 cover_corners[2][1] - inset + random.uniform(-3, 3)],
                [cover_corners[3][0] + ring_inset + random.uniform(-3, 3),
                 cover_corners[3][1] - inset + random.uniform(-3, 3)],
            ])
        else:
            paper_corners = np.float32([
                [cover_corners[0][0] + inset + random.uniform(-3, 3),
                 cover_corners[0][1] + inset + random.uniform(-3, 3)],
                [cover_corners[1][0] - ring_inset + random.uniform(-3, 3),
                 cover_corners[1][1] + inset + random.uniform(-3, 3)],
                [cover_corners[2][0] - ring_inset + random.uniform(-3, 3),
                 cover_corners[2][1] - inset + random.uniform(-3, 3)],
                [cover_corners[3][0] + inset + random.uniform(-3, 3),
                 cover_corners[3][1] - inset + random.uniform(-3, 3)],
            ])
        paper_corners = np.clip(paper_corners, 3, s - 3)

        # 용지 이미지 생성
        doc = self._generate_document()

        # 용지를 paper_corners 위치로 원근 변환
        doc_h, doc_w = doc.shape[:2]
        corners_src = np.float32([[0, 0], [doc_w, 0], [doc_w, doc_h], [0, doc_h]])
        M = cv2.getPerspectiveTransform(corners_src, paper_corners)
        warped_paper = cv2.warpPerspective(doc, M, (s, s),
                                            flags=cv2.INTER_LINEAR,
                                            borderMode=cv2.BORDER_CONSTANT,
                                            borderValue=(0, 0, 0))

        # 용지 마스크
        mask_paper = np.zeros((s, s), dtype=np.uint8)
        cv2.fillConvexPoly(mask_paper, paper_corners.astype(np.int32), 255)
        mask_paper_blur = cv2.GaussianBlur(mask_paper, (3, 3), 0)
        mask_paper_3ch = cv2.merge([mask_paper_blur] * 3).astype(np.float32) / 255.0

        result = (warped_paper.astype(np.float32) * mask_paper_3ch +
                  result.astype(np.float32) * (1 - mask_paper_3ch)).astype(np.uint8)

        # 4) 효과 적용
        result = self._apply_book_effects(result, paper_corners)
        result = self._apply_lighting(result)
        result = self._apply_shadow(result)
        result = self._apply_noise(result)
        result = self._apply_blur(result)
        result = self._apply_jpeg_artifact(result)

        # Ground truth = 용지의 코너 (정규화)
        normalized = paper_corners / s
        label = normalized.flatten()

        return result, label

    def generate_negative_sample(self) -> Tuple[np.ndarray, np.ndarray]:
        """문서가 없는 부정 샘플 (has_obj=0 학습용)"""
        bg = self._get_background_image()
        bg = self._apply_lighting(bg)
        bg = self._apply_noise(bg)

        # 코너 좌표는 0으로 (문서 없음)
        label = np.zeros(8, dtype=np.float32)
        return bg, label


def generate_dataset(
    output_dir: str,
    count: int = 5000,
    doc_dir: Optional[str] = None,
    bg_dir: Optional[str] = None,
    negative_ratio: float = 0.05,
    book_ratio: float = 0.4,
    binder_ratio: float = 0.0,
    visualize: bool = False,
    seed: int = 42,
):
    """전체 데이터셋 생성"""
    random.seed(seed)
    np.random.seed(seed)

    output_path = Path(output_dir)
    img_dir = output_path / "images"
    label_dir = output_path / "labels"
    img_dir.mkdir(parents=True, exist_ok=True)
    label_dir.mkdir(parents=True, exist_ok=True)

    if visualize:
        vis_dir = output_path / "visualize"
        vis_dir.mkdir(parents=True, exist_ok=True)

    print(f"=== 합성 데이터 생성 시작 ===")
    print(f"  출력: {output_path}")
    print(f"  총 수량: {count}")
    print(f"  책 비율: {book_ratio:.0%}")
    print(f"  바인더 비율: {binder_ratio:.0%}")
    print(f"  부정 샘플 비율: {negative_ratio:.0%}")

    generator = SyntheticDocumentGenerator(doc_dir, bg_dir, output_size=256)

    metadata = []
    neg_count = int(count * negative_ratio)
    binder_count = int((count - neg_count) * binder_ratio)
    book_count = int((count - neg_count - binder_count) * book_ratio)

    for i in range(count):
        if i < neg_count:
            img, label = generator.generate_negative_sample()
            sample_type = "negative"
        elif i < neg_count + binder_count:
            img, label = generator.generate_binder_sample()
            sample_type = "binder"
        elif i < neg_count + binder_count + book_count:
            img, label = generator.generate_sample(is_book=True)
            sample_type = "book"
        else:
            img, label = generator.generate_sample(is_book=False)
            sample_type = "document"

        # 저장
        img_path = img_dir / f"{i:05d}.jpg"
        label_path = label_dir / f"{i:05d}.npy"
        cv2.imwrite(str(img_path), img, [cv2.IMWRITE_JPEG_QUALITY, 95])
        np.save(str(label_path), label.astype(np.float32))

        metadata.append({
            "index": i,
            "type": sample_type,
            "corners": label.tolist(),
        })

        # 시각화 (처음 20장)
        if visualize and i < 20:
            vis = img.copy()
            if label.sum() > 0:
                corners = (label.reshape(4, 2) * 256).astype(np.int32)
                colors = [(0, 0, 255), (0, 255, 0), (255, 0, 0), (0, 255, 255)]  # R,G,B,Y for TL,TR,BR,BL
                labels = ["TL", "TR", "BR", "BL"]
                for j, (pt, color, lbl) in enumerate(zip(corners, colors, labels)):
                    cv2.circle(vis, tuple(pt), 5, color, -1)
                    cv2.putText(vis, lbl, (pt[0] + 7, pt[1] - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1)
                cv2.polylines(vis, [corners], True, (0, 255, 0), 2)
            else:
                cv2.putText(vis, "NO DOC", (80, 130), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)

            cv2.imwrite(str(vis_dir / f"vis_{i:05d}_{sample_type}.jpg"), vis)

        if (i + 1) % 500 == 0 or i == count - 1:
            print(f"  [{i + 1}/{count}] 생성 완료...")

    # 메타데이터 저장
    meta_path = output_path / "metadata.json"
    with open(meta_path, "w") as f:
        json.dump({
            "total": count,
            "negative": neg_count,
            "binder": binder_count,
            "book": book_count,
            "document": count - neg_count - binder_count - book_count,
            "output_size": 256,
            "corner_order": "TL,TR,BR,BL",
            "corner_format": "x0,y0,x1,y1,x2,y2,x3,y3 (normalized 0~1)",
            "samples": metadata,
        }, f, indent=2)

    # 학습/검증/테스트 분할 인덱스 저장
    indices = list(range(count))
    random.shuffle(indices)
    split_train = int(count * 0.8)
    split_val = int(count * 0.9)

    splits = {
        "train": sorted(indices[:split_train]),
        "val": sorted(indices[split_train:split_val]),
        "test": sorted(indices[split_val:]),
    }
    splits_path = output_path / "splits.json"
    with open(splits_path, "w") as f:
        json.dump(splits, f, indent=2)

    print(f"\n=== 생성 완료 ===")
    print(f"  이미지: {img_dir}")
    print(f"  라벨: {label_dir}")
    print(f"  메타데이터: {meta_path}")
    print(f"  분할: train={len(splits['train'])}, val={len(splits['val'])}, test={len(splits['test'])}")
    if visualize:
        print(f"  시각화: {vis_dir}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="합성 문서/책 코너 감지 학습 데이터 생성")
    parser.add_argument("--count", type=int, default=5000, help="생성할 총 이미지 수")
    parser.add_argument("--output", type=str, default="tools/training/dataset", help="출력 디렉터리")
    parser.add_argument("--doc-dir", type=str, default=None, help="외부 문서 이미지 디렉터리")
    parser.add_argument("--bg-dir", type=str, default=None, help="외부 배경 이미지 디렉터리")
    parser.add_argument("--negative-ratio", type=float, default=0.05, help="부정 샘플 비율")
    parser.add_argument("--book-ratio", type=float, default=0.4, help="책 페이지 샘플 비율")
    parser.add_argument("--binder-ratio", type=float, default=0.0, help="바인더 노트 샘플 비율")
    parser.add_argument("--visualize", action="store_true", help="시각화 이미지 생성")
    parser.add_argument("--seed", type=int, default=42, help="랜덤 시드")
    args = parser.parse_args()

    generate_dataset(
        output_dir=args.output,
        count=args.count,
        doc_dir=args.doc_dir,
        bg_dir=args.bg_dir,
        negative_ratio=args.negative_ratio,
        book_ratio=args.book_ratio,
        binder_ratio=args.binder_ratio,
        visualize=args.visualize,
        seed=args.seed,
    )

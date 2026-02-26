# -*- coding: utf-8 -*-
"""
Winote 문서 모서리 감지 테스트베드
=====================================
사용법:
  py tools/crop_testbed.py <이미지_경로> [옵션]

  py tools/crop_testbed.py "D:/OneDrive/잡폴더/Screenshot_20260224_231215.jpg"
  py tools/crop_testbed.py "D:/OneDrive/잡폴더/Screenshot_20260224_231215.jpg" --blob-max 0.85 --ymin-min 0.02
  py tools/crop_testbed.py "D:/OneDrive/잡폴더/Screenshot_20260224_231215.jpg" --strategy all --save

각 전략의 결과 이미지를 tools/output/ 폴더에 저장합니다.
"""

import sys
import os
import io
import argparse
import numpy as np
import cv2
import math
import matplotlib
matplotlib.use('Agg')  # GUI 없이 파일로 저장
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.font_manager as fm

# Windows 터미널 한국어 출력 설정
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

# matplotlib 한글 폰트 설정
def _setup_korean_font():
    candidates = [
        'Malgun Gothic', 'NanumGothic', 'AppleGothic', 'DejaVu Sans'
    ]
    available = {f.name for f in fm.fontManager.ttflist}
    for name in candidates:
        if name in available:
            matplotlib.rcParams['font.family'] = name
            break
    matplotlib.rcParams['axes.unicode_minus'] = False

_setup_korean_font()

# OpenCV imread 한글 경로 우회
def imread_unicode(path):
    """한글 경로를 포함한 이미지 읽기"""
    try:
        buf = np.fromfile(path, dtype=np.uint8)
        return cv2.imdecode(buf, cv2.IMREAD_COLOR)
    except Exception:
        return None

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)


# ─────────────────────────────────────────────
# 헬퍼 함수들 (Dart 코드와 동일한 로직)
# ─────────────────────────────────────────────

def order_corners(pts):
    """4점을 [TL, TR, BR, BL] 순서로 정렬"""
    pts = np.array(pts, dtype=np.float32)
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    tl = pts[np.argmin(s)]
    br = pts[np.argmax(s)]
    tr = pts[np.argmin(diff)]
    bl = pts[np.argmax(diff)]
    return [tl, tr, br, bl]


def is_convex_quad(pts):
    """볼록 사각형인지 확인"""
    pts = np.array(pts, dtype=np.float32).reshape(-1, 1, 2)
    return cv2.isContourConvex(pts)


def is_rectangular_enough(pts, max_angle_range=50.0):
    """내각이 max_angle_range 범위 이내인지 확인 (andrewdcampbell 방법)"""
    def get_angle(p1, vertex, p3):
        v1 = p1 - vertex
        v2 = p3 - vertex
        cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9)
        return math.degrees(math.acos(np.clip(cos_a, -1, 1)))

    tl, tr, br, bl = [np.array(p) for p in pts]
    angles = [
        get_angle(bl, tl, tr),
        get_angle(tl, tr, br),
        get_angle(tr, br, bl),
        get_angle(br, bl, tl),
    ]
    angle_range = max(angles) - min(angles)
    return angle_range <= max_angle_range, angles, angle_range


def quad_area(pts):
    """Shoelace 공식으로 사각형 면적 계산"""
    n = len(pts)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += pts[i][0] * pts[j][1]
        area -= pts[j][0] * pts[i][1]
    return abs(area) / 2


# ─────────────────────────────────────────────
# 전략별 함수
# ─────────────────────────────────────────────

def strategy_otsu_blob(gray, ww, wh, params):
    """
    전략 1: Otsu 이진화 → 밝은 blob → approxPolyDP
    params:
      blob_min: 최소 면적 비율 (기본 0.15)
      blob_max: 최대 면적 비율 (기본 0.65)
      ymin_min: yMin 최소값 비율 (기본 0.05, 이하면 배경으로 거부)
      max_angle: 최대 내각 범위 (기본 50.0)
    """
    blob_min = params.get('blob_min', 0.15)
    blob_max = params.get('blob_max', 0.65)
    ymin_min = params.get('ymin_min', 0.05)
    max_angle = params.get('max_angle', 50.0)
    logs = []

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    otsu_thresh, binary = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    logs.append(f"[Otsu] 자동 임계값={otsu_thresh:.1f}")

    k_size = max(11, min(41, int(ww * 0.04) | 1))
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (k_size, k_size))
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, k, iterations=3)
    opened = cv2.morphologyEx(closed, cv2.MORPH_OPEN, k, iterations=1)

    contours, _ = cv2.findContours(opened, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    logs.append(f"[Otsu] blob 개수={len(contours)}개")

    work_area = ww * wh
    best_quad = None
    best_score = 0
    all_candidates = []  # 시각화용

    for i, contour in enumerate(contours):
        area = cv2.contourArea(contour)
        ratio = area / work_area
        if ratio < blob_min or ratio > blob_max:
            logs.append(f"  blob{i}: 면적비={ratio:.2f} → 범위 외 제외 ({blob_min}~{blob_max})")
            continue

        perimeter = cv2.arcLength(contour, True)
        quad = None
        for eps in [0.02, 0.04, 0.06, 0.08, 0.10]:
            approx = cv2.approxPolyDP(contour, eps * perimeter, True)
            if len(approx) == 4:
                pts = [(p[0][0], p[0][1]) for p in approx]
                if is_convex_quad(pts):
                    ok, angles, angle_range = is_rectangular_enough(pts, max_angle)
                    if ok:
                        quad = order_corners(pts)
                        break

        if quad is None:
            logs.append(f"  blob{i}: 면적비={ratio:.2f} → 4각형 근사 실패")
            continue

        ys = [p[1] for p in quad]
        y_min = min(ys) / wh
        y_max = max(ys) / wh

        if y_min < ymin_min:
            logs.append(f"  blob{i}: 면적비={ratio:.2f} yMin={y_min:.2f} → 배경 포함(< {ymin_min}) 거부")
            all_candidates.append({'quad': quad, 'ratio': ratio, 'status': f'거부(yMin={y_min:.2f})', 'color': 'red'})
            continue
        if y_min > 0.40 or y_max < 0.60:
            logs.append(f"  blob{i}: 면적비={ratio:.2f} yMin={y_min:.2f} yMax={y_max:.2f} → 범위 외")
            continue

        score = quad_area(quad) / work_area
        logs.append(f"  blob{i}: 면적비={ratio:.2f} yMin={y_min:.2f} score={score:.3f} ✓")
        all_candidates.append({'quad': quad, 'ratio': ratio, 'status': f'후보({score:.3f})', 'color': 'yellow'})

        if score > best_score:
            best_score = score
            best_quad = quad

    if best_quad is not None:
        logs.append(f"[Otsu] 최종 선택: score={best_score:.3f}")
        all_candidates = [c for c in all_candidates if c['quad'] is not best_quad]
        all_candidates.append({'quad': best_quad, 'ratio': best_score, 'status': '최종선택', 'color': 'lime'})

    return best_quad, logs, {
        'binary': binary,
        'opened': opened,
        'candidates': all_candidates,
        'otsu_thresh': otsu_thresh,
    }


def strategy_canny_contour(gray, ww, wh, params):
    """
    전략 2: Canny 엣지 → contour → 가장 큰 4각형
    params:
      canny_low, canny_high: Canny 임계값 (기본 50, 150)
      blob_min, blob_max: 면적 비율 범위
      max_angle: 최대 내각 범위
    """
    canny_low = params.get('canny_low', 50)
    canny_high = params.get('canny_high', 150)
    blob_min = params.get('blob_min', 0.10)
    blob_max = params.get('blob_max', 0.90)
    max_angle = params.get('max_angle', 50.0)
    logs = []

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, canny_low, canny_high)
    logs.append(f"[Canny] 임계값=({canny_low}, {canny_high})")

    # 엣지 연결
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dilated = cv2.dilate(edges, k, iterations=1)

    contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    logs.append(f"[Canny] contour 개수={len(contours)}개")

    work_area = ww * wh
    best_quad = None
    best_score = 0
    all_candidates = []

    for i, contour in enumerate(sorted(contours, key=cv2.contourArea, reverse=True)[:10]):
        area = cv2.contourArea(contour)
        ratio = area / work_area
        if ratio < blob_min or ratio > blob_max:
            continue

        perimeter = cv2.arcLength(contour, True)
        quad = None
        for eps in [0.02, 0.04, 0.06, 0.08, 0.10]:
            approx = cv2.approxPolyDP(contour, eps * perimeter, True)
            if len(approx) == 4:
                pts = [(p[0][0], p[0][1]) for p in approx]
                if is_convex_quad(pts):
                    ok, angles, angle_range = is_rectangular_enough(pts, max_angle)
                    if ok:
                        quad = order_corners(pts)
                        break

        if quad is None:
            continue

        score = ratio
        logs.append(f"  contour{i}: 면적비={ratio:.2f} score={score:.3f} ✓")
        all_candidates.append({'quad': quad, 'ratio': ratio, 'status': f'후보({score:.3f})', 'color': 'yellow'})

        if score > best_score:
            best_score = score
            best_quad = quad

    if best_quad is not None:
        logs.append(f"[Canny] 최종 선택: score={best_score:.3f}")

    return best_quad, logs, {
        'edges': edges,
        'dilated': dilated,
        'candidates': all_candidates,
    }


def strategy_adaptive_thresh(gray, ww, wh, params):
    """
    전략 3: 적응형 이진화 (책 페이지 경계가 지역적으로 다른 밝기일 때 유리)
    """
    block_size = params.get('block_size', max(15, int(ww / 20) | 1))
    c_val = params.get('c_val', 5)
    blob_min = params.get('blob_min', 0.15)
    blob_max = params.get('blob_max', 0.85)
    max_angle = params.get('max_angle', 50.0)
    logs = []

    # CLAHE로 대비 강화
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    # 배경을 어둡게: Top-Hat (밝은 배경 위 어두운 책 경계 강조는 Black Top-Hat)
    k_large = cv2.getStructuringElement(cv2.MORPH_RECT, (int(ww * 0.15) | 1, int(wh * 0.15) | 1))
    blackhat = cv2.morphologyEx(enhanced, cv2.MORPH_BLACKHAT, k_large)
    logs.append(f"[Adaptive] block_size={block_size} C={c_val}")

    binary = cv2.adaptiveThreshold(enhanced, 255,
                                    cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                    cv2.THRESH_BINARY, block_size, c_val)
    binary = cv2.bitwise_not(binary)  # 반전: 책 경계 → 흰색

    k = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, k, iterations=3)

    contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    logs.append(f"[Adaptive] contour 개수={len(contours)}개")

    work_area = ww * wh
    best_quad = None
    best_score = 0
    all_candidates = []

    for i, contour in enumerate(sorted(contours, key=cv2.contourArea, reverse=True)[:10]):
        area = cv2.contourArea(contour)
        ratio = area / work_area
        if ratio < blob_min or ratio > blob_max:
            continue

        perimeter = cv2.arcLength(contour, True)
        quad = None
        for eps in [0.02, 0.04, 0.06, 0.08, 0.10]:
            approx = cv2.approxPolyDP(contour, eps * perimeter, True)
            if len(approx) == 4:
                pts = [(p[0][0], p[0][1]) for p in approx]
                if is_convex_quad(pts):
                    ok, angles, angle_range = is_rectangular_enough(pts, max_angle)
                    if ok:
                        quad = order_corners(pts)
                        break
        if quad is None:
            continue

        score = ratio
        logs.append(f"  contour{i}: 면적비={ratio:.2f} ✓")
        all_candidates.append({'quad': quad, 'ratio': ratio, 'status': f'후보({score:.3f})', 'color': 'yellow'})

        if score > best_score:
            best_score = score
            best_quad = quad

    if best_quad is not None:
        logs.append(f"[Adaptive] 최종 선택: score={best_score:.3f}")

    return best_quad, logs, {
        'binary': binary,
        'closed': closed,
        'candidates': all_candidates,
    }


def strategy_gradient(gray, ww, wh, params):
    """
    전략 4: Sobel 그래디언트 → 강한 엣지(책 모서리) → 사각형
    책 페이지와 배경의 경계에서 가장 강한 그래디언트 발생
    """
    logs = []
    blob_min = params.get('blob_min', 0.10)
    blob_max = params.get('blob_max', 0.90)
    max_angle = params.get('max_angle', 50.0)
    grad_thresh = params.get('grad_thresh', 50)

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    sobelx = cv2.Sobel(blurred, cv2.CV_64F, 1, 0, ksize=3)
    sobely = cv2.Sobel(blurred, cv2.CV_64F, 0, 1, ksize=3)
    magnitude = np.sqrt(sobelx**2 + sobely**2)
    magnitude = np.uint8(np.clip(magnitude / magnitude.max() * 255, 0, 255))
    _, binary = cv2.threshold(magnitude, grad_thresh, 255, cv2.THRESH_BINARY)
    logs.append(f"[Gradient] Sobel 그래디언트 임계={grad_thresh}")

    k = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, k, iterations=3)
    filled = cv2.morphologyEx(closed, cv2.MORPH_DILATE, k, iterations=2)

    contours, _ = cv2.findContours(filled, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    logs.append(f"[Gradient] contour 개수={len(contours)}개")

    work_area = ww * wh
    best_quad = None
    best_score = 0
    all_candidates = []

    for i, contour in enumerate(sorted(contours, key=cv2.contourArea, reverse=True)[:10]):
        area = cv2.contourArea(contour)
        ratio = area / work_area
        if ratio < blob_min or ratio > blob_max:
            continue

        perimeter = cv2.arcLength(contour, True)
        quad = None
        for eps in [0.02, 0.04, 0.06, 0.08, 0.10]:
            approx = cv2.approxPolyDP(contour, eps * perimeter, True)
            if len(approx) == 4:
                pts = [(p[0][0], p[0][1]) for p in approx]
                if is_convex_quad(pts):
                    ok, _, _ = is_rectangular_enough(pts, max_angle)
                    if ok:
                        quad = order_corners(pts)
                        break
        if quad is None:
            continue

        score = ratio
        logs.append(f"  contour{i}: 면적비={ratio:.2f} ✓")
        all_candidates.append({'quad': quad, 'ratio': ratio, 'status': f'후보({score:.3f})', 'color': 'yellow'})
        if score > best_score:
            best_score = score
            best_quad = quad

    if best_quad is not None:
        logs.append(f"[Gradient] 최종 선택: score={best_score:.3f}")

    return best_quad, logs, {
        'magnitude': magnitude,
        'closed': closed,
        'candidates': all_candidates,
    }


def _line_intersection(l1, l2):
    """두 직선(x1,y1,x2,y2)의 교점 반환. 평행이면 None."""
    x1,y1,x2,y2 = l1
    x3,y3,x4,y4 = l2
    denom = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4)
    if abs(denom) < 1e-9:
        return None
    t = ((x1-x3)*(y3-y4) - (y1-y3)*(x3-x4)) / denom
    x = x1 + t*(x2-x1)
    y = y1 + t*(y2-y1)
    return (x, y)


def strategy_line_intersection(gray, ww, wh, params):
    """
    전략 5 (핵심): HoughLinesP → 책 테두리 4직선 추출 → 교점으로 꼭짓점 계산
    - 책이 화면을 꽉 채워 모서리가 화면 밖으로 나간 경우에도 동작
    - 수평/수직선을 길이 기준으로 정렬하여 상단/하단, 좌측/우측 직선을 선택
    - 화면 밖 교점(clamp)도 허용
    """
    logs = []
    hough_thresh = params.get('hough_thresh', 30)
    min_len_ratio = params.get('min_len_ratio', 0.15)

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 30, 90)

    min_len = max(ww, wh) * min_len_ratio
    lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=hough_thresh,
                             minLineLength=min_len, maxLineGap=30)

    if lines is None:
        logs.append("[Lines] HoughLinesP 직선 없음")
        return None, logs, {'edges': edges}

    logs.append(f"[Lines] 직선 수={len(lines)}, minLen={min_len:.0f}")

    # 수평(±20°) / 수직(70~110°) 분류, 길이 포함
    horiz, vert = [], []
    for l in lines:
        x1,y1,x2,y2 = l[0]
        angle = math.degrees(math.atan2(abs(y2-y1), abs(x2-x1)))
        length = math.sqrt((x2-x1)**2+(y2-y1)**2)
        if angle < 20:
            horiz.append((x1,y1,x2,y2,length))
        elif angle > 70:
            vert.append((x1,y1,x2,y2,length))

    logs.append(f"[Lines] 수평={len(horiz)}개 수직={len(vert)}개")

    if len(horiz) < 2 or len(vert) < 2:
        logs.append("[Lines] 수평/수직 직선 부족")
        return None, logs, {'edges': edges}

    # 수평선: y 중간값으로 정렬 → 가장 위(상단 후보군), 가장 아래(하단 후보군)
    def mid_y(l): return (l[1] + l[3]) / 2
    def mid_x(l): return (l[0] + l[2]) / 2
    horiz_sorted = sorted(horiz, key=mid_y)
    vert_sorted = sorted(vert, key=mid_x)

    # 상위 30%에서 가장 긴 것 = 상단 직선, 하위 30%에서 가장 긴 것 = 하단 직선
    n_h = max(1, len(horiz_sorted) // 3)
    top_line = max(horiz_sorted[:n_h], key=lambda l: l[4])
    bot_line = max(horiz_sorted[-n_h:], key=lambda l: l[4])

    n_v = max(1, len(vert_sorted) // 3)
    left_line = max(vert_sorted[:n_v], key=lambda l: l[4])
    right_line = max(vert_sorted[-n_v:], key=lambda l: l[4])

    # 핵심 보완: 상단/하단 직선이 너무 가까우면 → 책이 화면 위/아래로 삐져나온 케이스
    # 상단이 화면 상단 30% 안에 없으면 → 화면 경계(y=0)를 상단선으로 사용
    # 하단이 화면 하단 70% 밖이면 → 화면 경계(y=wh)를 하단선으로 사용
    if mid_y(top_line) > wh * 0.30:
        logs.append(f"[Lines] 상단선 없음(y_mid={mid_y(top_line):.0f} > {wh*0.30:.0f}) → 화면 상단(y=0) 사용")
        top_line = (0, 0, ww, 0, ww)  # 화면 최상단 가상 수평선
    if mid_y(bot_line) < wh * 0.50:
        logs.append(f"[Lines] 하단선 없음(y_mid={mid_y(bot_line):.0f} < {wh*0.50:.0f}) → 화면 하단 사용")
        bot_line = (0, wh, ww, wh, ww)  # 화면 최하단 가상 수평선

    # 같은 직선이 선택된 경우 (상단=하단) → 분리
    if mid_y(top_line) >= mid_y(bot_line) - wh * 0.2:
        if len(horiz_sorted) >= 2:
            top_line = max(horiz_sorted[:max(1, len(horiz_sorted)//2)], key=lambda l: l[4])
            bot_line = max(horiz_sorted[len(horiz_sorted)//2:], key=lambda l: l[4])
        else:
            logs.append("[Lines] 상단/하단 직선 구분 실패")
            return None, logs, {'edges': edges}

    logs.append(f"[Lines] 상단: ({top_line[0]},{top_line[1]})->({top_line[2]},{top_line[3]}) "
                f"y_mid={mid_y(top_line):.0f}")
    logs.append(f"[Lines] 하단: ({bot_line[0]},{bot_line[1]})->({bot_line[2]},{bot_line[3]}) "
                f"y_mid={mid_y(bot_line):.0f}")
    logs.append(f"[Lines] 좌측: ({left_line[0]},{left_line[1]})->({left_line[2]},{left_line[3]}) "
                f"x_mid={mid_x(left_line):.0f}")
    logs.append(f"[Lines] 우측: ({right_line[0]},{right_line[1]})->({right_line[2]},{right_line[3]}) "
                f"x_mid={mid_x(right_line):.0f}")

    # 4개 교점 계산
    tl = _line_intersection(top_line[:4], left_line[:4])
    tr = _line_intersection(top_line[:4], right_line[:4])
    br = _line_intersection(bot_line[:4], right_line[:4])
    bl = _line_intersection(bot_line[:4], left_line[:4])

    if None in (tl, tr, br, bl):
        logs.append("[Lines] 교점 계산 실패 (평행선)")
        return None, logs, {'edges': edges}

    # 범위 clamp: 화면 밖 교점도 20% 여유까지 허용
    margin = 0.20
    for pt, name in [(tl,'TL'), (tr,'TR'), (br,'BR'), (bl,'BL')]:
        x, y = pt
        if x < -ww*margin or x > ww*(1+margin) or y < -wh*margin or y > wh*(1+margin):
            logs.append(f"[Lines] {name} 교점 범위 초과: ({x:.0f},{y:.0f})")
            return None, logs, {'edges': edges}

    quad = order_corners([tl, tr, br, bl])
    logs.append(f"[Lines] 꼭짓점: TL{tuple(int(v) for v in quad[0])} "
                f"TR{tuple(int(v) for v in quad[1])} "
                f"BR{tuple(int(v) for v in quad[2])} "
                f"BL{tuple(int(v) for v in quad[3])}")

    # 직사각형 검증
    ok, angles, angle_range = is_rectangular_enough(quad, max_angle_range=60.0)
    if not ok:
        logs.append(f"[Lines] 직사각형 검증 실패: 각도범위={angle_range:.1f}°")
        return None, logs, {'edges': edges}

    # 시각화용 직선 이미지
    line_vis = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
    for l, color in [(top_line, (0,255,0)), (bot_line, (0,200,0)),
                     (left_line, (255,0,0)), (right_line, (200,0,0))]:
        cv2.line(line_vis, (l[0],l[1]), (l[2],l[3]), color, 2)

    return quad, logs, {'edges': edges, 'line_vis': line_vis}


# ─────────────────────────────────────────────
# 결과 시각화 및 저장
# ─────────────────────────────────────────────

def draw_result(image, quad, candidates, title, logs, output_path):
    """결과 이미지를 matplotlib으로 저장"""
    h, w = image.shape[:2]
    fig, axes = plt.subplots(1, 2, figsize=(16, 10))
    fig.suptitle(title, fontsize=14, fontweight='bold')

    # 왼쪽: 원본 + 감지 결과
    ax_orig = axes[0]
    display = image.copy()
    if len(display.shape) == 2:
        display = cv2.cvtColor(display, cv2.COLOR_GRAY2RGB)
    else:
        display = cv2.cvtColor(display, cv2.COLOR_BGR2RGB)

    # 후보들 그리기
    for c in candidates:
        q = c['quad']
        color_map = {'red': (255, 50, 50), 'yellow': (255, 200, 50), 'lime': (50, 255, 50)}
        color = color_map.get(c['color'], (200, 200, 200))
        pts = np.array(q, dtype=np.int32)
        cv2.polylines(display, [pts], True, color, 2)

    # 최종 결과 그리기 (두껍게)
    if quad is not None:
        pts = np.array(quad, dtype=np.int32)
        cv2.polylines(display, [pts], True, (0, 200, 255), 4)
        labels = ['TL', 'TR', 'BR', 'BL']
        for i, (p, lbl) in enumerate(zip(quad, labels)):
            cv2.circle(display, (int(p[0]), int(p[1])), 12, (0, 200, 255), -1)
            cv2.putText(display, lbl, (int(p[0]) + 5, int(p[1]) - 5),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

    ax_orig.imshow(display)
    ax_orig.set_title(f'감지 결과 ({"✅ 성공" if quad is not None else "❌ 실패"})')
    ax_orig.axis('off')

    # 오른쪽: 로그 출력
    ax_log = axes[1]
    ax_log.axis('off')
    log_text = '\n'.join(logs)
    ax_log.text(0.02, 0.98, log_text, transform=ax_log.transAxes,
               fontsize=9, verticalalignment='top', fontfamily='monospace',
               bbox=dict(boxstyle='round', facecolor='black', alpha=0.8),
               color='lime')
    ax_log.set_title('처리 로그')

    # 범례
    patches = [
        mpatches.Patch(color='lime', label='최종 선택'),
        mpatches.Patch(color='yellow', label='후보'),
        mpatches.Patch(color='red', label='거부됨'),
        mpatches.Patch(color='cyan', label='최종 꼭짓점'),
    ]
    ax_orig.legend(handles=patches, loc='lower right', fontsize=8)

    plt.tight_layout()
    plt.savefig(output_path, dpi=120, bbox_inches='tight')
    plt.close()
    print(f"  저장: {output_path}")


def draw_intermediate(data, title, output_path):
    """중간 처리 이미지(이진화, 엣지 등) 저장"""
    items = [(k, v) for k, v in data.items() if isinstance(v, np.ndarray)]
    if not items:
        return

    n = len(items)
    fig, axes = plt.subplots(1, n, figsize=(6 * n, 5))
    fig.suptitle(f'{title} - 중간 처리 단계', fontsize=12)
    if n == 1:
        axes = [axes]

    for ax, (name, img) in zip(axes, items):
        if len(img.shape) == 2:
            ax.imshow(img, cmap='gray')
        else:
            ax.imshow(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        ax.set_title(name)
        ax.axis('off')

    plt.tight_layout()
    plt.savefig(output_path, dpi=100, bbox_inches='tight')
    plt.close()
    print(f"  중간단계 저장: {output_path}")


# ─────────────────────────────────────────────
# 메인
# ─────────────────────────────────────────────

def run(image_path, strategy='all', params=None, save=True, work_size=640):
    if params is None:
        params = {}

    print(f"\n{'='*60}")
    print(f"이미지: {image_path}")
    print(f"전략: {strategy} | 파라미터: {params}")
    print(f"{'='*60}")

    image = imread_unicode(image_path)
    if image is None:
        print(f"[ERROR] 이미지를 읽을 수 없습니다: {image_path}")
        return

    orig_h, orig_w = image.shape[:2]
    scale = min(1.0, work_size / max(orig_w, orig_h))
    ww = int(orig_w * scale)
    wh = int(orig_h * scale)
    work = cv2.resize(image, (ww, wh)) if scale < 1.0 else image.copy()
    gray = cv2.cvtColor(work, cv2.COLOR_BGR2GRAY)

    print(f"원본 크기: {orig_w}x{orig_h} → 작업 크기: {ww}x{wh} (scale={scale:.2f})")

    basename = os.path.splitext(os.path.basename(image_path))[0]

    strategies = {
        'otsu': ('Otsu Blob', strategy_otsu_blob),
        'canny': ('Canny Contour', strategy_canny_contour),
        'adaptive': ('Adaptive Thresh', strategy_adaptive_thresh),
        'gradient': ('Sobel Gradient', strategy_gradient),
        'lines': ('Line Intersection', strategy_line_intersection),
    }

    targets = list(strategies.items()) if strategy == 'all' else [(strategy, strategies[strategy])]

    results_summary = []
    for key, (name, fn) in targets:
        print(f"\n▶ 전략: {name}")
        quad, logs, debug_data = fn(gray, ww, wh, params)

        # 스케일 역변환
        if quad is not None and scale < 1.0:
            quad = [(p[0] / scale, p[1] / scale) for p in quad]
            if 'candidates' in debug_data:
                for c in debug_data['candidates']:
                    c['quad'] = [(p[0] / scale, p[1] / scale) for p in c['quad']]

        for log in logs:
            print(f"  {log}")

        status = "✅ 성공" if quad is not None else "❌ 실패"
        print(f"  → {status}")
        results_summary.append((name, status, quad))

        if save:
            out_result = os.path.join(OUTPUT_DIR, f"{basename}_{key}_result.jpg")
            out_debug = os.path.join(OUTPUT_DIR, f"{basename}_{key}_debug.jpg")
            draw_result(image, quad, debug_data.get('candidates', []),
                       f"{name} - {os.path.basename(image_path)}", logs, out_result)
            debug_imgs = {k: v for k, v in debug_data.items() if isinstance(v, np.ndarray)}
            if debug_imgs:
                draw_intermediate(debug_imgs, name, out_debug)

    # 요약
    print(f"\n{'='*60}")
    print("전략별 결과 요약:")
    for name, status, quad in results_summary:
        if quad is not None:
            ys = [p[1] / orig_h for p in quad]
            xs = [p[0] / orig_w for p in quad]
            coord_str = f"TL({xs[0]:.2f},{ys[0]:.2f}) TR({xs[1]:.2f},{ys[1]:.2f}) BR({xs[2]:.2f},{ys[2]:.2f}) BL({xs[3]:.2f},{ys[3]:.2f})"
            print(f"  {name}: {status} → {coord_str}")
        else:
            print(f"  {name}: {status}")
    print(f"{'='*60}")
    if save:
        print(f"\n결과 이미지 저장 위치: {OUTPUT_DIR}")


def main():
    parser = argparse.ArgumentParser(description='Winote 문서 모서리 감지 테스트베드')
    parser.add_argument('image', help='테스트할 이미지 경로')
    parser.add_argument('--strategy', default='all',
                        choices=['all', 'otsu', 'canny', 'adaptive', 'gradient', 'lines'],
                        help='테스트할 전략 (기본: all)')
    parser.add_argument('--blob-min', type=float, default=0.15, help='최소 blob 면적 비율 (기본: 0.15)')
    parser.add_argument('--blob-max', type=float, default=0.85, help='최대 blob 면적 비율 (기본: 0.85)')
    parser.add_argument('--ymin-min', type=float, default=0.05, help='yMin 최소값 비율 (기본: 0.05)')
    parser.add_argument('--max-angle', type=float, default=50.0, help='최대 내각 범위 도 (기본: 50.0)')
    parser.add_argument('--canny-low', type=int, default=50, help='Canny 낮은 임계값 (기본: 50)')
    parser.add_argument('--canny-high', type=int, default=150, help='Canny 높은 임계값 (기본: 150)')
    parser.add_argument('--work-size', type=int, default=640, help='작업 이미지 크기 (기본: 640)')
    parser.add_argument('--save', action='store_true', default=True, help='결과 이미지 저장 (기본: True)')
    parser.add_argument('--no-save', dest='save', action='store_false', help='결과 이미지 저장 안 함')

    args = parser.parse_args()

    params = {
        'blob_min': args.blob_min,
        'blob_max': args.blob_max,
        'ymin_min': args.ymin_min,
        'max_angle': args.max_angle,
        'canny_low': args.canny_low,
        'canny_high': args.canny_high,
    }

    run(args.image, strategy=args.strategy, params=params, save=args.save, work_size=args.work_size)


if __name__ == '__main__':
    main()

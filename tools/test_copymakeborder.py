"""
copyMakeBorder 트릭 - 문서/책 4꼭짓점 감지 정확도 비교 테스트베드
=============================================================
전략 A: 그냥 Canny + findContours (현재 방식)
전략 B: copyMakeBorder(10px 검은 여백) + Canny + findContours
전략 C: copyMakeBorder + GaussianBlur(7,7,2.0) + Canny(30,90) + dilate + findContours
전략 D: copyMakeBorder + morphologyEx(CLOSE) + Canny + findContours

Windows 환경, 한글 경로 우회(np.fromfile + cv2.imdecode) 적용
"""

import sys
import os

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

import numpy as np
import cv2

# ─────────────────────────────────────────────
# 경로 설정
# ─────────────────────────────────────────────
TOOLS_DIR = "H:/Claude_work/Winote/tools"
OUTPUT_DIR = os.path.join(TOOLS_DIR, "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

TEST_IMAGES = [
    os.path.join(TOOLS_DIR, "real_book_230308.jpg"),
    os.path.join(TOOLS_DIR, "real_book_230722.jpg"),
    os.path.join(TOOLS_DIR, "real_book_231215.jpg"),
]

BORDER_SIZE = 10   # copyMakeBorder 여백 픽셀


# ─────────────────────────────────────────────
# 유틸: 한글 경로 안전 imread / imwrite
# ─────────────────────────────────────────────
def safe_imread(path):
    arr = np.fromfile(path, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    return img


def safe_imwrite(path, img):
    ext = os.path.splitext(path)[1]
    ret, buf = cv2.imencode(ext, img)
    if ret:
        buf.tofile(path)
        return True
    return False


# ─────────────────────────────────────────────
# 전처리: 그레이 + 리사이즈
# ─────────────────────────────────────────────
def preprocess(img, max_side=800):
    h, w = img.shape[:2]
    scale = min(max_side / max(h, w), 1.0)
    if scale < 1.0:
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    return img, gray, scale


# ─────────────────────────────────────────────
# 4꼭짓점 추출 공통 로직
#   - 입력: Canny 엣지 맵 (+ 선택적 dilate)
#   - 출력: 4점(ndarray shape=(4,2)) or None
# ─────────────────────────────────────────────
def find_quad(edge_map):
    contours, _ = cv2.findContours(edge_map, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    # 면적 기준 상위 5개 후보
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]

    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < edge_map.shape[0] * edge_map.shape[1] * 0.05:
            continue  # 너무 작은 윤곽선 무시

        peri = cv2.arcLength(cnt, True)
        for eps_ratio in [0.02, 0.03, 0.04, 0.06, 0.08]:
            approx = cv2.approxPolyDP(cnt, eps_ratio * peri, True)
            if len(approx) == 4:
                return approx.reshape(4, 2).astype(np.float32)

    return None


# ─────────────────────────────────────────────
# 결과 시각화: 원본 이미지에 꼭짓점 표시
#   pts: shape=(4,2) float32, offset_x/y: 여백 보정값
# ─────────────────────────────────────────────
def draw_result(img_color, pts, offset_x=0, offset_y=0, color=(0, 255, 0)):
    vis = img_color.copy()
    if pts is None:
        # 감지 실패 → 빨간 × 표시
        h, w = vis.shape[:2]
        cv2.line(vis, (0, 0), (w, h), (0, 0, 255), 3)
        cv2.line(vis, (w, 0), (0, h), (0, 0, 255), 3)
        cv2.putText(vis, "FAIL", (w // 2 - 40, h // 2),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 0, 255), 3)
        return vis

    pts_shifted = pts.copy()
    pts_shifted[:, 0] -= offset_x
    pts_shifted[:, 1] -= offset_y
    pts_int = pts_shifted.astype(np.int32)

    cv2.polylines(vis, [pts_int], True, color, 3)
    for i, (x, y) in enumerate(pts_int):
        cv2.circle(vis, (x, y), 10, (0, 0, 255), -1)
        cv2.putText(vis, str(i), (x + 5, y - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 0), 2)
    return vis


# ─────────────────────────────────────────────
# 품질 점수: 4점이 이미지 전체 면적 대비 얼마나 큰가
# ─────────────────────────────────────────────
def quad_score(pts, img_h, img_w, offset_x=0, offset_y=0):
    if pts is None:
        return 0.0
    pts_shifted = pts.copy()
    pts_shifted[:, 0] -= offset_x
    pts_shifted[:, 1] -= offset_y
    # 클리핑
    pts_shifted[:, 0] = np.clip(pts_shifted[:, 0], 0, img_w - 1)
    pts_shifted[:, 1] = np.clip(pts_shifted[:, 1], 0, img_h - 1)
    area_quad = cv2.contourArea(pts_shifted.astype(np.float32))
    area_img = img_h * img_w
    return area_quad / area_img


# ─────────────────────────────────────────────
# 전략 A: 현재 방식 (여백 없음)
# ─────────────────────────────────────────────
def strategy_A(gray):
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    blurred = cv2.GaussianBlur(enhanced, (5, 5), 1.0)

    best_pts = None
    for lo, hi in [(50, 150), (30, 100), (75, 200), (20, 60)]:
        edges = cv2.Canny(blurred, lo, hi)
        pts = find_quad(edges)
        if pts is not None:
            best_pts = pts
            break
    return best_pts, 0, 0   # offset = 0


# ─────────────────────────────────────────────
# 전략 B: copyMakeBorder(10px) + Canny
# ─────────────────────────────────────────────
def strategy_B(gray):
    bordered = cv2.copyMakeBorder(
        gray, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE,
        cv2.BORDER_CONSTANT, value=0
    )
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(bordered)
    blurred = cv2.GaussianBlur(enhanced, (5, 5), 1.0)

    best_pts = None
    for lo, hi in [(50, 150), (30, 100), (75, 200), (20, 60)]:
        edges = cv2.Canny(blurred, lo, hi)
        pts = find_quad(edges)
        if pts is not None:
            best_pts = pts
            break
    return best_pts, BORDER_SIZE, BORDER_SIZE


# ─────────────────────────────────────────────
# 전략 C: copyMakeBorder + GaussianBlur(7,7,2.0) + Canny(30,90) + dilate
# ─────────────────────────────────────────────
def strategy_C(gray):
    bordered = cv2.copyMakeBorder(
        gray, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE,
        cv2.BORDER_CONSTANT, value=0
    )
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(bordered)
    blurred = cv2.GaussianBlur(enhanced, (7, 7), 2.0)

    best_pts = None
    for lo, hi in [(30, 90), (50, 150), (20, 60), (15, 45)]:
        edges = cv2.Canny(blurred, lo, hi)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        edges = cv2.dilate(edges, kernel, iterations=1)
        pts = find_quad(edges)
        if pts is not None:
            best_pts = pts
            break
    return best_pts, BORDER_SIZE, BORDER_SIZE


# ─────────────────────────────────────────────
# 전략 D: copyMakeBorder + morphologyEx(CLOSE) + Canny
# ─────────────────────────────────────────────
def strategy_D(gray):
    bordered = cv2.copyMakeBorder(
        gray, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE, BORDER_SIZE,
        cv2.BORDER_CONSTANT, value=0
    )
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(bordered)
    blurred = cv2.GaussianBlur(enhanced, (5, 5), 1.0)

    # Canny 먼저 → CLOSE 모폴로지로 끊긴 엣지 연결
    best_pts = None
    for lo, hi in [(50, 150), (30, 100), (75, 200), (20, 60)]:
        edges = cv2.Canny(blurred, lo, hi)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel)
        pts = find_quad(closed)
        if pts is not None:
            best_pts = pts
            break
    return best_pts, BORDER_SIZE, BORDER_SIZE


# ─────────────────────────────────────────────
# 복합 전략 (B+C+D 앙상블): 점수 기반 최적 선택
# ─────────────────────────────────────────────
def strategy_best(gray):
    results = {}
    results["B"] = strategy_B(gray)
    results["C"] = strategy_C(gray)
    results["D"] = strategy_D(gray)

    h, w = gray.shape
    best_name = None
    best_score = -1
    for name, (pts, ox, oy) in results.items():
        s = quad_score(pts, h, w, ox, oy)
        print(f"    [{name}] score={s:.3f}, pts={'OK' if pts is not None else 'FAIL'}")
        if s > best_score:
            best_score = s
            best_name = name

    pts, ox, oy = results[best_name]
    print(f"    → 최적 전략: {best_name} (score={best_score:.3f})")
    return pts, ox, oy, best_name


# ─────────────────────────────────────────────
# 메인 실행
# ─────────────────────────────────────────────
def run_all():
    strategies = {
        "A_no_border": strategy_A,
        "B_border_canny": strategy_B,
        "C_border_blur_dilate": strategy_C,
        "D_border_morph_close": strategy_D,
    }

    total_results = {}  # {img_name: {strategy: score}}

    for img_path in TEST_IMAGES:
        img_name = os.path.splitext(os.path.basename(img_path))[0]
        print(f"\n{'='*60}")
        print(f"이미지: {img_name}")
        print(f"{'='*60}")

        img = safe_imread(img_path)
        if img is None:
            print(f"  ⚠ 이미지 로드 실패: {img_path}")
            continue

        img_resized, gray, scale = preprocess(img, max_side=800)
        h, w = img_resized.shape[:2]
        print(f"  원본 크기: {img.shape[1]}x{img.shape[0]} → 리사이즈: {w}x{h} (scale={scale:.2f})")

        row_imgs = [img_resized]  # 비교 이미지 가로 나열용
        row_labels = ["원본"]
        img_scores = {}

        for strat_name, strat_fn in strategies.items():
            print(f"\n  전략 {strat_name}:")
            try:
                if strat_fn == strategy_A:
                    pts, ox, oy = strat_fn(gray)
                else:
                    pts, ox, oy = strat_fn(gray)

                score = quad_score(pts, h, w, ox, oy)
                img_scores[strat_name] = score
                status = "✅ 감지 성공" if pts is not None else "❌ 감지 실패"
                print(f"    {status}, 면적비={score:.3f}")

                vis = draw_result(img_resized, pts, ox, oy)

                # 레이블 추가
                label_bar = np.zeros((40, vis.shape[1], 3), dtype=np.uint8)
                score_str = f"{strat_name}: {score:.3f}"
                color = (0, 255, 0) if pts is not None else (0, 0, 255)
                cv2.putText(label_bar, score_str, (5, 28),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
                vis_labeled = np.vstack([label_bar, vis])
                row_imgs.append(vis_labeled)
                row_labels.append(strat_name)

                # 개별 저장
                out_path = os.path.join(OUTPUT_DIR, f"{img_name}_{strat_name}.jpg")
                safe_imwrite(out_path, vis)
                print(f"    저장: {out_path}")

            except Exception as e:
                print(f"    ⚠ 예외 발생: {e}")
                img_scores[strat_name] = 0.0

        total_results[img_name] = img_scores

        # 원본 이미지에도 레이블 추가
        orig_bar = np.zeros((40, img_resized.shape[1], 3), dtype=np.uint8)
        cv2.putText(orig_bar, "Original", (5, 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        row_imgs[0] = np.vstack([orig_bar, img_resized])

        # 모든 이미지 높이 통일 후 가로 합성
        max_h = max(im.shape[0] for im in row_imgs)
        padded = []
        for im in row_imgs:
            dh = max_h - im.shape[0]
            if dh > 0:
                pad = np.zeros((dh, im.shape[1], 3), dtype=np.uint8)
                im = np.vstack([im, pad])
            padded.append(im)

        comparison = np.hstack(padded)
        comp_path = os.path.join(OUTPUT_DIR, f"{img_name}_comparison.jpg")
        safe_imwrite(comp_path, comparison)
        print(f"\n  비교 이미지 저장: {comp_path}")

        # 앙상블 (최적 전략 자동 선택)
        print(f"\n  [앙상블] 최적 전략 자동 선택:")
        best_pts, best_ox, best_oy, best_name = strategy_best(gray)
        best_vis = draw_result(img_resized, best_pts, best_ox, best_oy,
                               color=(255, 165, 0))
        best_path = os.path.join(OUTPUT_DIR, f"{img_name}_BEST_{best_name}.jpg")
        safe_imwrite(best_path, best_vis)
        print(f"    저장: {best_path}")

    # ─── 최종 요약 ───
    print(f"\n{'='*60}")
    print("최종 결과 요약 (면적비: 1.0에 가까울수록 정확)")
    print(f"{'='*60}")
    header = f"{'이미지':<22} {'A(기본)':<12} {'B(여백)':<12} {'C(블러+다일)':<14} {'D(모폴로지)':<14}"
    print(header)
    print("-" * len(header))

    A_wins, B_wins, C_wins, D_wins = 0, 0, 0, 0
    for img_name, scores in total_results.items():
        a = scores.get("A_no_border", 0)
        b = scores.get("B_border_canny", 0)
        c = scores.get("C_border_blur_dilate", 0)
        d = scores.get("D_border_morph_close", 0)
        best = max(a, b, c, d)
        row = f"{img_name:<22} {a:<12.3f} {b:<12.3f} {c:<14.3f} {d:<14.3f}"
        print(row)
        if best == a:
            A_wins += 1
        elif best == b:
            B_wins += 1
        elif best == c:
            C_wins += 1
        else:
            D_wins += 1

    print(f"\n전략별 1등 횟수: A={A_wins}, B={B_wins}, C={C_wins}, D={D_wins}")
    print(f"\n결과 이미지 저장 폴더: {OUTPUT_DIR}")
    print("완료!")


if __name__ == "__main__":
    run_all()

import sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

import numpy as np
import onnxruntime as ort
import cv2

model_path = 'H:/Claude_work/Winote/assets/models/lcnet050_p_multi_decoder_l3_d64_256_fp32.onnx'
sess = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])

def imread_unicode(path):
    buf = np.fromfile(path, dtype=np.uint8)
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)

def detect_corners(img_path):
    img = imread_unicode(img_path)
    if img is None:
        print('이미지 로드 실패:', img_path)
        return None

    h, w = img.shape[:2]
    print('이미지 크기: %dx%d' % (w, h))

    # 전처리: 256x256 리사이즈 -> float32 [0,1] -> NCHW
    resized = cv2.resize(img, (256, 256))
    inp = np.transpose(resized, (2, 0, 1)).astype(np.float32)[None] / 255.0

    # 추론
    result = sess.run(None, {'img': inp})
    points = result[0][0]    # shape (8,)
    has_obj = float(result[1][0][0])

    status = '문서 감지됨' if has_obj > 0.5 else '문서 없음'
    print('has_obj: %.3f (%s)' % (has_obj, status))

    if has_obj > 0.5:
        pts = points.reshape(4, 2)
        # 정규화 좌표(0~1) -> 원본 픽셀 좌표
        pts_px = pts * np.array([w, h])
        labels = ['TL', 'TR', 'BR', 'BL']
        for i, (x, y) in enumerate(pts_px):
            print('  %s: (%.2f, %.2f) = (%d, %d)' % (labels[i], x/w, y/h, int(x), int(y)))

        # 결과 이미지 저장
        out = img.copy()
        pts_int = pts_px.astype(np.int32)
        cv2.polylines(out, [pts_int], True, (0, 255, 0), 3)
        for i, (x, y) in enumerate(pts_px):
            cv2.circle(out, (int(x), int(y)), 10, (0, 0, 255), -1)
            cv2.putText(out, labels[i], (int(x)+5, int(y)-5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 0), 2)

        name = img_path.split('/')[-1].replace('.jpg', '')
        out_path = 'H:/Claude_work/Winote/tools/output/docaligner_%s.jpg' % name
        os.makedirs('H:/Claude_work/Winote/tools/output', exist_ok=True)
        cv2.imencode('.jpg', out)[1].tofile(out_path)
        print('결과 저장:', out_path)
        return pts_px
    return None


test_images = [
    # 원본 스크린샷 (앱 UI 포함)
    'D:/OneDrive/잡폴더/Screenshot_20260224_230308.jpg',
    'D:/OneDrive/잡폴더/Screenshot_20260224_230722.jpg',
    'D:/OneDrive/잡폴더/Screenshot_20260224_231215.jpg',
    'D:/OneDrive/잡폴더/Screenshot_20260224_233411.jpg',
    # 잘라낸 이미지 (책만)
    'H:/Claude_work/Winote/tools/real_book_230308.jpg',
    'H:/Claude_work/Winote/tools/real_book_230722.jpg',
    'H:/Claude_work/Winote/tools/real_book_231215.jpg',
]

for img_path in test_images:
    name = img_path.split('/')[-1]
    print('\n=== %s ===' % name)
    detect_corners(img_path)

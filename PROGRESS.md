# PROGRESS.md (현재 진행: 얇게 유지)

## Dashboard
- Progress: 스캐너 품질 개선 완료 — confidence 앙상블 + 흐림감지 + convex 체크 + 메모리 안전성
- Risk: 낮음 (17장 실기기 테스트 16/17 성공, 91.7% 성공률)

## What changed (2026-02-25)
- **🧠 DocAligner v2: 바인더 노트 합성 데이터 추가 + 재학습**
  - **문제**: 실기기 테스트에서 바인더 노트 커버 전체를 문서로 오감지 (9장 테스트)
  - **해결**: `generate_binder_sample()` 합성 데이터 생성기 추가
    - 바인더 커버(어두운 색) + 금속 링 + 내부 용지 합성
    - Ground truth = 용지 코너만 (커버가 아닌 내부 용지)
  - **데이터**: 7,000장 (binder 30%, book 30%, document 35%, negative 5%)
  - **학습 v2**: Stage 2 (백본+헤드), 20 epochs, LR=5e-5
    - **val_dist=2.02px** (v1: 2.56px → 21% 개선), ok=100%
    - Test: dist=2.05px, success=100%
  - ONNX export: `doc_aligner_book_v2.onnx` (4.72MB), INT8 2.17MB
  - Flutter `doc_aligner_service.dart` → v2 모델로 교체
  - **APK + Windows 빌드 + `D:\OneDrive\코드작업\Winote\` 배포 완료**
- **🔄 자동 스캔에 DocAligner v2 적용**
  - `detectCornersFromYPlane()` 추가: Y plane → 256×256 리사이즈 + NCHW 변환 + ONNX 추론
  - `scanner_page.dart` `_processFrame`: DocAligner 우선 → OpenCV fallback 전략
- **✅ 실기기 테스트 통과 (5장)**
  - 바인더 노트 (손글씨/텍스트/컬러이미지/기울어짐) 모두 정상 감지
  - v1 대비: 커버 오감지 문제 완전 해결, 용지 영역만 정확히 검출
  - 미세 여백(1~2%) 존재하나 실사용 무영향
- **이전 모델 백업**:
  - v1 체크포인트: `checkpoints/archive_stage2_v1/`
  - v2 체크포인트: `checkpoints/archive_stage2_v2/`
  - v1 ONNX: `assets/models/archive/`

## 현재 상태
- **활성 모델 (v2 INT8)**: `assets/models/doc_aligner_book_v2_int8.onnx` (2.17MB)
- **INT8 양자화**: `assets/models/doc_aligner_book_v2_int8.onnx` (2.17MB)
- **학습 체크포인트**: `tools/training/checkpoints/checkpoint_best.pt` (v2, epoch 20)
- **학습 코드**: `tools/training/train.py`, `generate_synthetic_data.py`, `export_onnx.py`
- **배포**: `D:\OneDrive\코드작업\Winote\` (winote.exe + Winote-debug.apk)

## Open issues
- 합성 데이터만으로 학습 → 더 다양한 실제 환경에서 추가 검증 필요

## Next
- [x] ~~실기기 바인더 노트 테스트 (v2 모델 검증)~~ ✅ 17장 테스트 (5+12)
- [x] ~~INT8 모델(`2.17MB`)로 전환~~ ✅ 적용 완료
- [x] ~~confidence 기반 DL+OpenCV 앙상블~~ ✅ 가중 평균 전략 적용
- [x] ~~품질 평가 보강~~ ✅ 흐림 감지(Laplacian) + convex quad 체크
- [x] ~~메모리/dispose 안전성~~ ✅ 버퍼/타이머 정리 강화
- [ ] 추가 실패 케이스 발견 시 → 데이터 보강 → 재학습 (v3)

---

## Previous (아카이브 대상)
- 2026-02-24: OpenCV 스캐너 Phase 1~3 완료, 실기기 튜닝 10회+
- 2026-02-23: EMA 스무딩, Otsu 적응형, 다중 스케일 감지
- 2026-02-22: QR/바코드, 스마트 배치, vFlat 초월 기능
- 상세: `ARCHIVE_2026_02.md` 참조

---
## Archive Rule
- 완료 항목이 20개를 넘거나 파일이 5KB를 넘으면,
  완료된 내용을 `ARCHIVE_YYYY_MM.md`로 옮기고 PROGRESS는 "현재 이슈"만 남긴다.

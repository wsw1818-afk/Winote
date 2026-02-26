# 스캔 기능 개선 및 버그 보완 기획서

## 📊 현재 상태 요약

### 완료된 기능
- **DocAligner v2**: 바인더 노트 감지 문제 해결 (합성 데이터 7,000장으로 fine-tuned)
- **INT8 양자화**: 모델 크기 2.17MB로 최적화
- **EMA 스무딩**: 경계선 흔들림 감소
- **자동 스캔**: 품질 평가 + 안정 프레임 카운트 기반 자동 촬영
- **배치 모드**: 연속 촬영 지원
- **음성 명령**: "촬영", "찍어", "캡처", "스캔" 키워드 인식

### 현재 아키텍처
```
카메라 프레임 → Y plane 추출 → DocAligner v2 (ONNX) → OpenCV fallback
                     ↓
              EMA 스무딩 + 버퍼 평균
                     ↓
              품질 평가 → 자동 촬영
```

---

## 🐛 버그 및 개선 필요 사항

### 1. 우선순위 높음 (Critical)

#### 1.1 메모리 누수 가능성
**문제점**:
- [`scanner_page.dart`](lib/presentation/pages/scanner/scanner_page.dart:61)에서 `Timer? _countdownTimer` 사용
- `_onCameraFrame`에서 `Uint8List.fromList(yPlane.bytes)` 매 프레임마다 새 리스트 생성
- `_cornerBuffer`가 무제한으로 성장 가능 (현재는 `removeAt(0)`로 제어하지만 경계 조건 확인 필요)

**해결 방안**:
```dart
// 1. Y plane 복사 최소화 - 직접 참조 사용 검토
final yBytes = yPlane.bytes; // Uint8List.view 사용 고려

// 2. dispose()에서 확실한 정리
@override
void dispose() {
  _stopAutoDetection();
  _stopListening();
  _countdownTimer?.cancel();  // 명시적 취소
  _cornerBuffer.clear();       // 버퍼 정리
  _cameraController?.dispose();
  super.dispose();
}
```

#### 1.2 동시성 이슈 (Race Condition)
**문제점**:
- [`_isDetecting`](lib/presentation/pages/scanner/scanner_page.dart:75) 플래그가 `setState`와 무관하게 변경됨
- `_processFrame`이 비동기인데 `_isDetecting = false`가 `finally`에서만 실행됨
- 예외 발생 시 `_isDetecting`이 영구히 `true`로 고정될 가능성

**해결 방안**:
```dart
// 스레드 안전한 상태 관리
bool _isDetecting = false;
final _detectionLock = Object();

Future<void> _processFrame(...) async {
  if (!mounted) return;
  
  synchronized(_detectionLock) {
    if (_isDetecting) return;
    _isDetecting = true;
  }
  
  try {
    // ... 처리 로직
  } catch (e) {
    debugPrint('프레임 처리 실패: $e');
  } finally {
    if (mounted) {
      _isDetecting = false;
    }
  }
}
```

#### 1.3 카메라 권한 처리 미흡
**문제점**:
- [`_initCamera()`](lib/presentation/pages/scanner/scanner_page.dart:154)에서 예외 발생 시 단순히 `_isCameraAvailable = false`로 설정
- 사용자에게 권한 요청 안내가 없음
- 권한 거부 시 재요청 메커니즘 없음

**해결 방안**:
```dart
Future<void> _initCamera() async {
  // 1. 권한 확인 및 요청
  final status = await Permission.camera.status;
  if (!status.isGranted) {
    final result = await Permission.camera.request();
    if (!result.isGranted) {
      _showPermissionDialog();
      return;
    }
  }
  
  // 2. 기존 초기화 로직...
}

void _showPermissionDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('카메라 권한 필요'),
      content: const Text('스캔 기능을 사용하려면 카메라 권한이 필요합니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(
          onPressed: () => openAppSettings(),
          child: const Text('설정으로 이동'),
        ),
      ],
    ),
  );
}
```

---

### 2. 우선순위 중간 (Major)

#### 2.1 DocAligner 신뢰도 기반 전략 전환
**문제점**:
- 현재는 DocAligner 성공 시 무조건 사용, 실패 시 OpenCV fallback
- `has_obj` 임계값(0.5)이 고정되어 있어 경계 케이스에서 잘못된 감지 가능

**해결 방안**:
```dart
// confidence 기반 앙상블 전략
Future<List<Offset>?> _processFrame(...) async {
  final dlResult = await DocAlignerService.instance.detectCornersFromYPlane(...);
  
  // confidence 값 반환 추가 필요
  final dlConfidence = dlResult?.confidence ?? 0.0;
  
  if (dlConfidence > 0.8) {
    // 높은 신뢰도: DL 결과 사용
    return dlResult?.corners;
  } else if (dlConfidence > 0.5) {
    // 중간 신뢰도: DL + OpenCV 가중 평균
    final cvResult = await DocumentScannerService.instance.detectCornersFromGrayscale(...);
    return _blendCorners(dlResult!.corners, cvResult, dlConfidence);
  } else {
    // 낮은 신뢰도: OpenCV만 사용
    return await DocumentScannerService.instance.detectCornersFromGrayscale(...);
  }
}
```

#### 2.2 스무딩 알고리즘 개선
**문제점**:
- [`_applySmoothingToCorners()`](lib/presentation/pages/scanner/scanner_page.dart:393)에서 중앙값 기반 outlier 제거 사용
- x축 임계값(0.08), y축 임계값(0.12)이 하드코딩
- 빠른 움직임에 대한 응답성과 안정성 사이의 트레이드오프

**해결 방안**:
```dart
// 적응형 스무딩 - 문서 이동 속도에 따라 알고리즘 전환
List<Offset>? _applyAdaptiveSmoothing(List<Offset> newCorners) {
  final velocity = _calculateVelocity(newCorners);
  
  if (velocity > 0.3) {
    // 빠른 이동: 즉시 업데이트 (버퍼 초기화)
    _cornerBuffer.clear();
    _cornerBuffer.add(List.from(newCorners));
    return List.from(newCorners);
  } else if (velocity > 0.1) {
    // 중간 속도: 짧은 버퍼로 빠른 응답
    _smoothingFactor = 0.4; // 더 빠른 반응
  } else {
    // 느린 이동/정지: 긴 버퍼로 안정화
    _smoothingFactor = 0.15; // 더 부드러운 결과
  }
  
  return _applySmoothingToCorners(newCorners);
}
```

#### 2.3 품질 평가 기준 보완
**문제점**:
- [`_quickQuality()`](lib/presentation/pages/scanner/scanner_page.dart:335)에서 밝기, 영역 크기, 각도만 평가
- 흐림(blur), 반사광, 그림자 등 실제 품질 요소 미반영

**해결 방안**:
```dart
Map<String, dynamic> _enhancedQuality(
  List<Offset> corners, 
  double avgBright,
  Uint8List yBytes, int w, int h, int bytesPerRow,
) {
  final issues = <String>[];
  double score = 100.0;
  
  // 1. 기존 평가 (조명, 크기, 각도)
  // ...
  
  // 2. 흐림 감지 (Laplacian variance)
  final blurScore = _detectBlur(yBytes, w, h, bytesPerRow);
  if (blurScore < 100) {
    issues.add('이미지가 흐림');
    score -= 30;
  }
  
  // 3. 반사광 감지 (국소 과밝기 영역)
  final glareRatio = _detectGlare(yBytes, w, h, bytesPerRow);
  if (glareRatio > 0.1) {
    issues.add('반사광이 감지됨');
    score -= 15;
  }
  
  // 4. 코너 일관성 (convex hull 여부)
  if (!_isConvexQuad(corners)) {
    issues.add('영역이 올바르지 않음');
    score -= 25;
  }
  
  return {
    'isGood': score >= 70 && issues.isEmpty,
    'score': score.clamp(0.0, 100.0),
    'issues': issues,
    'blurScore': blurScore,
    'glareRatio': glareRatio,
  };
}

double _detectBlur(Uint8List bytes, int w, int h, int bytesPerRow) {
  // Laplacian variance 계산 (간소화 버전)
  double variance = 0;
  int count = 0;
  for (int y = 1; y < h - 1; y += 4) {
    for (int x = 1; x < w - 1; x += 4) {
      final idx = y * bytesPerRow + x;
      final laplacian = -4 * bytes[idx] 
          + bytes[idx - 1] + bytes[idx + 1] 
          + bytes[idx - bytesPerRow] + bytes[idx + bytesPerRow];
      variance += laplacian * laplacian;
      count++;
    }
  }
  return count > 0 ? variance / count : 0;
}
```

#### 2.4 배치 모드 UX 개선
**문제점**:
- 배치 촬영 중 진행 상황 표시 미흡
- 썸네일 미리보기 없음
- 개별 이미지 삭제/재촬영 기능 없음

**해결 방안**:
```dart
// 배치 모드 개선 위젯
Widget _buildBatchProgress() {
  return Container(
    height: 100,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _batchImages.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ImageThumbnail(_batchImages[index]),
            // 삭제 버튼
            Positioned(
              top: 0, right: 0,
              child: IconButton(
                icon: Icon(Icons.close, size: 16),
                onPressed: () => _removeBatchImage(index),
              ),
            ),
            // 순서 표시
            Positioned(
              bottom: 0, left: 0,
              child: CircleAvatar(
                radius: 10,
                child: Text('${index + 1}'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
```

---

### 3. 우선순위 낮음 (Minor)

#### 3.1 접근성 개선
- 자동 스캔 카운트다운 시 시각+진동 피드백 추가
- 음성 안내 기능 (VoiceOver/TalkBack 지원 강화)
- 색상 대비 개선 (경계선 오버레이)

#### 3.2 성능 최적화
- ONNX 추론 스레드 풀 사용 (현재 단일 스레드)
- 프레임 스킵 전략 도입 (저사양 기기 대응)
- 메모리 캐시 크기 제한

#### 3.3 에러 처리 강화
- 네트워크 오류, 저장 공간 부족 등 구체적 에러 메시지
- 재시도 메커니즘 (자동 재시도 + 수동 재시도)
- 에러 로깅 및 크래시리틱스 연동

---

## 📋 구현 로드맵

### Phase 1: 버그 수정 (1주)
- [ ] 메모리 누수 수정
- [ ] 동시성 이슈 해결
- [ ] 카메라 권한 처리 개선
- [ ] dispose() 정리 로직 강화

### Phase 2: 품질 개선 (2주)
- [ ] DocAligner confidence 기반 전략 구현
- [ ] 적응형 스무딩 알고리즘 적용
- [ ] 품질 평가 기준 보완 (흐림, 반사광 감지)
- [ ] 배치 모드 UX 개선

### Phase 3: 사용자 경험 (1주)
- [ ] 접근성 개선
- [ ] 에러 처리 강화
- [ ] 성능 최적화

---

## 🧪 테스트 계획

### 단위 테스트
- [ ] `_applySmoothingToCorners` 알고리즘 테스트
- [ ] `_quickQuality` 품질 평가 로직 테스트
- [ ] `_isDefaultCorners` 경계 조건 테스트

### 통합 테스트
- [ ] 카메라 권한 시나리오 테스트
- [ ] 배치 모드 전체 플로우 테스트
- [ ] 메모리 누수 테스트 (반복 촬영 100회)

### 실기기 테스트
- [ ] 다양한 조명 조건 (어두움/밝음/역광)
- [ ] 다양한 문서 타입 (책/노트/명함/영수증)
- [ ] 저사양 기기에서의 성능 검증

---

## 📝 참고 사항

### 관련 파일
- [`lib/presentation/pages/scanner/scanner_page.dart`](lib/presentation/pages/scanner/scanner_page.dart) - 메인 스캐너 UI
- [`lib/core/services/doc_aligner_service.dart`](lib/core/services/doc_aligner_service.dart) - ONNX 기반 문서 감지
- [`lib/core/services/document_scanner_service.dart`](lib/core/services/document_scanner_service.dart) - OpenCV 기반 처리
- [`lib/presentation/pages/scanner/crop_page.dart`](lib/presentation/pages/scanner/crop_page.dart) - 크롭 UI
- [`lib/presentation/pages/scanner/filter_page.dart`](lib/presentation/pages/scanner/filter_page.dart) - 필터 UI

### 관련 이슈
- PROGRESS.md: Open issues - 합성 데이터만으로 학습 → 더 다양한 실제 환경 검증 필요
- PROGRESS.md: Next - OpenCV + DL 앙상블: confidence 기반 선택 전략

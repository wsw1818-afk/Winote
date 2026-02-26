import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'crop_page.dart';
import 'filter_page.dart' show ScanInsertMode;
import '../../../core/services/document_scanner_service.dart';
import '../../../core/services/doc_aligner_service.dart';

/// 스캔 진입 모드
enum ScanEntryMode {
  /// 독립 실행 (홈에서 진입, 저장만 가능)
  standalone,

  /// 에디터에서 진입 (노트에 삽입/배경 설정 가능)
  fromEditor,
}

/// 카메라 미리보기 + 촬영 / 파일 선택 페이지
class ScannerPage extends StatefulWidget {
  final ScanEntryMode entryMode;

  /// 에디터에서 진입 시 결과 이미지 경로를 반환하는 콜백
  /// null이면 standalone 모드
  final void Function(String imagePath, ScanInsertMode mode)? onResult;

  const ScannerPage({
    super.key,
    this.entryMode = ScanEntryMode.standalone,
    this.onResult,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCameraAvailable = false;
  bool _isCapturing = false;

  // 연속 촬영 모드
  bool _batchMode = false;
  final List<String> _batchImages = [];

  // 자동 스캔 모드 (vFlat 스타일)
  bool _autoMode = true; // 기본값: 자동
  int _lastDetectionMs = 0; // 프레임 스로틀링
  List<Offset>? _detectedCorners;
  Map<String, dynamic>? _qualityInfo;
  DocumentSize? _documentSize; // vFlat 초월: 문서 크기 측정
  int _stableFrameCount = 0; // 안정적 감지 프레임 수
  int _autoCountdown = 0; // 자동 촬영 카운트다운
  Timer? _countdownTimer; // 카운트다운 타이머 (누수 방지)
  static const int _requiredStableFrames = 2; // 자동 촬영에 필요한 안정 프레임 수 (빠른 오토스캔)

  // 스마트 배치: 다중 문서 동시 감지
  List<List<Offset>>? _detectedMultiDocs; // 여러 문서 경계선
  bool _showCapturedFeedback = false; // 촬영 완료 피드백
  int _smartBatchCaptureCount = 0; // 스마트 배치 촬영 수

  // 경계선 안정화 (EMA smoothing + 프레임 버퍼)
  List<Offset>? _smoothedCorners; // 스무딩된 코너 좌표
  static const double _smoothingFactor = 0.20; // EMA 계수: 낮출수록 흔들림 감소 (우상 y 안정화)
  static const int _bufferSize = 3; // 최근 N프레임 (빠른 반응 + EMA가 안정화 담당)
  final List<List<Offset>> _cornerBuffer = []; // 최근 감지 버퍼
  int _noDetectionCount = 0; // 연속 미감지 횟수
  bool _isDetecting = false; // 감지 중 중복 호출 방지

  // vFlat 초월: 음성 명령 촬영
  bool _voiceMode = false; // 음성 명령 모드
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initSpeech();
  }

  /// 음성 인식 초기화
  Future<void> _initSpeech() async {
    try {
      _speechInitialized = await _speech.initialize(
        onError: (error) => debugPrint('음성 인식 에러: $error'),
        onStatus: (status) => debugPrint('음성 인식 상태: $status'),
      );
      if (_speechInitialized && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('음성 인식 초기화 실패: $e');
    }
  }

  /// 음성 인식 시작
  void _startListening() {
    if (!_speechInitialized) return;
    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        // "촬영", "찍어", "캡처", "스캔" 등 키워드 감지
        if (words.contains('촬영') ||
            words.contains('찍어') ||
            words.contains('캡처') ||
            words.contains('스캔')) {
          _captureImage();
          _speech.stop();
        }
      },
      localeId: 'ko_KR', // 한국어
    );
  }

  /// 음성 인식 정지
  void _stopListening() {
    _speech.stop();
  }

  /// 카메라 이미지 스트림 시작 (초점 방해 없이 프레임 읽기)
  void _startAutoDetection() {
    if (!_autoMode) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;
    try {
      _cameraController!.startImageStream(_onCameraFrame);
      debugPrint('[스캐너] 이미지 스트림 시작 성공');
    } catch (e) {
      debugPrint('[스캐너] 이미지 스트림 시작 실패: $e');
    }
  }

  /// 이미지 스트림 + 카운트다운 정지
  void _stopAutoDetection() {
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('이미지 스트림 정지 실패: $e');
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _isCameraAvailable = false;
        });
        return;
      }

      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.high, // 스트림 방식이므로 고해상도 유지
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // 연속 자동 초점 활성화 (startImageStream 중에도 AF 유지)
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        debugPrint('[스캐너] 자동 초점 모드 설정 완료');
      } catch (e) {
        debugPrint('[스캐너] 자동 초점 설정 실패: $e');
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isCameraAvailable = true;
        });
        // 자동 감지 시작
        _startAutoDetection();
      }
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _isCameraAvailable = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stopAutoDetection();
    _stopListening();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _cornerBuffer.clear();
    _cameraController?.dispose();
    super.dispose();
  }

  /// 카메라 프레임 콜백 (startImageStream → 초점 방해 없음)
  void _onCameraFrame(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDetectionMs < 350) return; // 350ms 스로틀링 (빠른 감지 + ONNX 부하 균형)
    if (_isDetecting || _isCapturing || _showCapturedFeedback) return;

    _lastDetectionMs = now;
    _isDetecting = true;

    // Y plane 추출 — 버퍼 직접 참조 (복사 최소화)
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final width = image.width;
    final height = image.height;
    final bytesPerRow = yPlane.bytesPerRow;

    // Android 센서는 보통 가로(landscape) 방향 → 세로 모드에서 회전 필요
    final sensorOrientation = _cameras?.first.sensorOrientation ?? 0;
    final needsRotation = (sensorOrientation == 90 || sensorOrientation == 270)
        && width > height;

    _processFrame(yBytes, width, height, bytesPerRow, needsRotation);
  }

  /// 프레임 비동기 처리: DocAligner v2 (딥러닝) 단독 사용 (OpenCV fallback 제거 — 성능 최우선)
  Future<void> _processFrame(
    Uint8List yBytes, int width, int height, int bytesPerRow,
    bool needsRotation,
  ) async {
    try {
      // DocAligner v2 단일 추론만 (OpenCV fallback 완전 제거 — 추론 1회로 제한)
      final dlResult = await DocAlignerService.instance
          .detectCornersFromYPlane(yBytes, width, height, bytesPerRow,
              needsRotation: needsRotation);

      if (!mounted) return;

      List<Offset>? corners;
      double dlConfidence = 0.0;
      if (dlResult != null && dlResult.corners.length == 4) {
        corners = dlResult.corners;
        dlConfidence = dlResult.confidence;
      }

      final isDefault = corners == null || _isDefaultCorners(corners);

      if (isDefault) {
        _noDetectionCount++;
        // 5회 연속 미감지 시에만 경계선 초기화 (책 접힘 시 잠깐 놓쳐도 유지)
        if (_noDetectionCount >= 5) {
          _cornerBuffer.clear();
          _stableFrameCount = 0;
          _autoCountdown = 0;
          setState(() {
            _detectedCorners = null;
            _smoothedCorners = null;
            _qualityInfo = {'isGood': false, 'score': 0.0, 'issues': <String>['문서를 찾을 수 없음']};
            _documentSize = null;
          });
        }
      } else {
        _noDetectionCount = 0;
        final smoothed = _applySmoothingToCorners(corners!);

        // null = 노이즈 프레임 → 이전 값 그대로 유지
        if (smoothed == null) {
          _isDetecting = false;
          return;
        }

        // 경량 품질 평가 (밝기 샘플링 최소화 + 코너 기하학)
        final avgBright = _averageBrightnessFast(yBytes, width, height, bytesPerRow);
        final quality = _quickQuality(corners, avgBright);
        final isGood = quality['isGood'] == true;

        // setState 1회로 통합 (UI 리빌드 최소화)
        if (isGood) { _stableFrameCount++; } else { _stableFrameCount = 0; _autoCountdown = 0; }
        setState(() {
          _detectedCorners = smoothed;
          _smoothedCorners = smoothed;
          _qualityInfo = quality;
        });

        // 자동 촬영 트리거
        if (isGood && _stableFrameCount >= _requiredStableFrames && _autoCountdown == 0) {
          if (dlConfidence > 0.85) {
            // 고신뢰도: 카운트다운 없이 즉시 촬영
            _captureImage();
          } else {
            _startAutoCountdown();
          }
        }
      }
    } catch (e) {
      debugPrint('프레임 처리 실패: $e');
    } finally {
      _isDetecting = false;
    }
  }

  /// Y plane 평균 밝기 (64픽셀 간격 초고속 샘플링 — 성능 최우선)
  double _averageBrightnessFast(Uint8List yBytes, int w, int h, int bytesPerRow) {
    int sum = 0;
    int count = 0;
    for (int y = 0; y < h; y += 64) {
      for (int x = 0; x < w; x += 64) {
        final idx = y * bytesPerRow + x;
        if (idx < yBytes.length) { sum += yBytes[idx]; count++; }
      }
    }
    return count > 0 ? sum / count : 128;
  }

  /// 경량 품질 평가 (코너 + 밝기 + convex 체크, 파일 I/O 없음)
  Map<String, dynamic> _quickQuality(List<Offset> corners, double avgBright) {
    final issues = <String>[];
    double score = 100.0;

    // 조명
    final lightScore = (avgBright / 255 * 100).clamp(0.0, 100.0);
    if (lightScore < 30) { issues.add('너무 어두움'); score -= 25; }
    else if (lightScore > 92) { issues.add('너무 밝음'); score -= 20; }

    // 문서 영역 크기 (정규화 좌표 → 면적 0~1)
    double area = 0;
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      area += corners[i].dx * corners[j].dy;
      area -= corners[j].dx * corners[i].dy;
    }
    area = area.abs() / 2;
    if (area < 0.15) { issues.add('문서가 너무 작음'); score -= 25; }

    // 각도 (대변 비율)
    final sides = <double>[];
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      final dx = corners[j].dx - corners[i].dx;
      final dy = corners[j].dy - corners[i].dy;
      sides.add(math.sqrt(dx * dx + dy * dy));
    }
    final r1 = sides[0] > 0 ? math.min(sides[0], sides[2]) / math.max(sides[0], sides[2]) : 0.0;
    final r2 = sides[1] > 0 ? math.min(sides[1], sides[3]) / math.max(sides[1], sides[3]) : 0.0;
    final angleScore = ((r1 + r2) / 2 * 100).clamp(0.0, 100.0);
    if (angleScore < 60) { issues.add('각도가 기울어짐'); score -= 20; }

    // Convex quad 체크 (외적 부호가 모두 같아야 볼록 사각형)
    if (!_isConvexQuad(corners)) {
      issues.add('영역이 올바르지 않음');
      score -= 25;
    }

    return {
      'isGood': score >= 70 && issues.isEmpty,
      'score': score.clamp(0.0, 100.0),
      'issues': issues,
    };
  }

  /// 볼록 사각형 여부 확인 (외적 부호 일관성)
  bool _isConvexQuad(List<Offset> corners) {
    if (corners.length != 4) return false;
    bool? positive;
    for (int i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) continue; // 거의 일직선
      if (positive == null) {
        positive = cross > 0;
      } else if ((cross > 0) != positive) {
        return false; // 오목
      }
    }
    return true;
  }

  /// 기본 코너인지 확인 (감지 실패 시 반환되는 값)
  bool _isDefaultCorners(List<Offset> corners) {
    if (corners.length != 4) return true;
    // 기본값: (0.05, 0.05), (0.95, 0.05), (0.95, 0.95), (0.05, 0.95)
    final defaultCorners = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
    double totalDist = 0;
    for (int i = 0; i < 4; i++) {
      totalDist += (corners[i] - defaultCorners[i]).distance;
    }
    return totalDist < 0.02; // 거의 기본값과 같으면 미감지로 판단
  }

  /// 버퍼 평균 + EMA 스무딩: 최근 N프레임 평균 → EMA 적용
  /// null 반환 = 큰 점프 직후 버퍼 초기화 중 (이전 값 유지)
  List<Offset>? _applySmoothingToCorners(List<Offset> newCorners) {
    // 매우 큰 점프(>0.50) 감지: 완전히 새 문서 배치 → 버퍼 초기화 후 즉시 업데이트
    // (0.35 → 0.50으로 완화: 책 접힌 경우 모서리가 크게 변동해도 같은 문서)
    if (_smoothedCorners != null && _smoothedCorners!.length == 4) {
      double maxDelta = 0;
      for (int i = 0; i < 4; i++) {
        final d = (newCorners[i] - _smoothedCorners![i]).distance;
        if (d > maxDelta) maxDelta = d;
      }
      if (maxDelta > 0.50) {
        _cornerBuffer.clear();
        _cornerBuffer.add(List.from(newCorners));
        return List.from(newCorners);
      }
    }

    // 버퍼에 추가 (최대 _bufferSize개 유지)
    _cornerBuffer.add(List.from(newCorners));
    if (_cornerBuffer.length > _bufferSize) {
      _cornerBuffer.removeAt(0);
    }

    // 버퍼가 2개 미만이면 첫 프레임 그대로
    if (_cornerBuffer.length < 2) return List.from(newCorners);

    // 버퍼 평균 계산 (꼭짓점별 중앙값 기반 outlier 제거)
    // 평균 대신 중앙값(median)을 기준으로 outlier 제거
    // x축: 0.08 (좌상 0.25 오감지 등 x 이상값 엄격 제거)
    // y축: 0.12 (우상 y=0.01↔0.13 같은 작은 흔들림은 허용하되 극단값만 제거)
    final avgCorners = List.generate(4, (i) {
      final dxs = _cornerBuffer.map((f) => f[i].dx).toList()..sort();
      final dys = _cornerBuffer.map((f) => f[i].dy).toList()..sort();
      final medDx = dxs[dxs.length ~/ 2];
      final medDy = dys[dys.length ~/ 2];
      const outlierThreshX = 0.08; // x축: 좌상 0.25 오감지 등 제거에 엄격
      const outlierThreshY = 0.12; // y축: 약간의 흔들림은 허용
      final filtDx = dxs.where((v) => (v - medDx).abs() <= outlierThreshX).toList();
      final filtDy = dys.where((v) => (v - medDy).abs() <= outlierThreshY).toList();
      final dx = filtDx.isEmpty ? medDx : filtDx.reduce((a, b) => a + b) / filtDx.length;
      final dy = filtDy.isEmpty ? medDy : filtDy.reduce((a, b) => a + b) / filtDy.length;
      return Offset(dx, dy);
    });

    // EMA 적용 (이전 스무딩값 × (1-α) + 버퍼평균 × α)
    if (_smoothedCorners == null || _smoothedCorners!.length != 4) {
      return avgCorners;
    }
    return List.generate(4, (i) => Offset(
      _smoothedCorners![i].dx * (1 - _smoothingFactor) + avgCorners[i].dx * _smoothingFactor,
      _smoothedCorners![i].dy * (1 - _smoothingFactor) + avgCorners[i].dy * _smoothingFactor,
    ));
  }

  /// 자동 촬영 카운트다운 시작 (1초 카운트다운 → 즉시 촬영)
  void _startAutoCountdown() {
    _countdownTimer?.cancel(); // 기존 타이머 정리
    setState(() => _autoCountdown = 1);

    _countdownTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _countdownTimer = null;
      setState(() => _autoCountdown = 0);
      _captureImage();
    });
  }

  /// 카메라로 촬영 (스트림 정지 → 촬영 → 스트림 재시작)
  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    // 스트림 정지 (takePicture와 동시 사용 불가)
    _stopAutoDetection();

    try {
      final xFile = await _cameraController!.takePicture();

      if (_batchMode) {
        setState(() {
          _batchImages.add(xFile.path);
          _isCapturing = false;
          _stableFrameCount = 0;
          _autoCountdown = 0;
          _noDetectionCount = 0;
          _smartBatchCaptureCount++;
        });

        if (_autoMode && mounted) {
          setState(() => _showCapturedFeedback = true);
          await Future.delayed(const Duration(milliseconds: 1200));
          if (mounted) {
            setState(() {
              _showCapturedFeedback = false;
              _detectedCorners = null;
              _smoothedCorners = null;
              _qualityInfo = null;
              _detectedMultiDocs = null;
            });
            _startAutoDetection(); // 스트림 재시작
          }
        }
      } else {
        if (mounted) {
          _navigateToCrop(xFile.path);
        }
      }
    } catch (e) {
      debugPrint('촬영 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('촬영 실패: $e')),
        );
        // 실패 시 스트림 재시작
        if (_autoMode) _startAutoDetection();
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// 파일에서 이미지 선택
  Future<void> _pickFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: _batchMode,
      );

      if (result == null || result.files.isEmpty) return;

      if (_batchMode) {
        for (final file in result.files) {
          if (file.path != null) {
            setState(() => _batchImages.add(file.path!));
          }
        }
      } else {
        final filePath = result.files.first.path;
        if (filePath != null && mounted) {
          _navigateToCrop(filePath);
        }
      }
    } catch (e) {
      debugPrint('파일 선택 실패: $e');
    }
  }

  /// 갤러리에서 이미지 선택 (image_picker 사용)
  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (_batchMode) {
        setState(() => _batchImages.add(picked.path));
      } else {
        if (mounted) {
          _navigateToCrop(picked.path);
        }
      }
    } catch (e) {
      debugPrint('갤러리 선택 실패: $e');
    }
  }

  /// 크롭 페이지로 이동 (돌아오면 스트림 재시작)
  void _navigateToCrop(String imagePath) {
    _stopAutoDetection(); // 다른 페이지 이동 시 스트림 정지
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropPage(
          imagePath: imagePath,
          entryMode: widget.entryMode,
          onResult: widget.onResult,
        ),
      ),
    ).then((_) {
      if (mounted && _autoMode && _isCameraAvailable) {
        _startAutoDetection();
      }
    });
  }

  /// 배치 모드에서 완료 → 필터 페이지로
  void _finishBatch() {
    if (_batchImages.isEmpty) return;

    // 스마트 배치 상태 리셋
    _stopAutoDetection();
    setState(() {
      _smartBatchCaptureCount = 0;
      _detectedMultiDocs = null;
      _showCapturedFeedback = false;
    });

    // 첫 번째 이미지부터 크롭 시작 (나머지는 순차 처리)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropPage(
          imagePath: _batchImages.first,
          batchImages: _batchImages,
          entryMode: widget.entryMode,
          onResult: widget.onResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('문서 스캔'),
        actions: [
          // 자동 모드 토글 (vFlat 스타일)
          IconButton(
            icon: Icon(
              _autoMode ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              color: _autoMode ? Colors.green : Colors.white,
            ),
            tooltip: '자동 촬영 모드',
            onPressed: () {
              setState(() {
                _autoMode = !_autoMode;
                if (_autoMode) {
                  _startAutoDetection();
                } else {
                  _stopAutoDetection();
                  _detectedCorners = null;
                  _smoothedCorners = null;
                  _qualityInfo = null;
                  _stableFrameCount = 0;
                  _autoCountdown = 0;
                  _noDetectionCount = 0;
                }
              });
            },
          ),
          // vFlat 초월: 음성 명령 모드
          if (_speechInitialized)
            IconButton(
              icon: Icon(
                _voiceMode ? Icons.mic : Icons.mic_none,
                color: _voiceMode ? Colors.blue : Colors.white,
              ),
              tooltip: '음성 명령 촬영',
              onPressed: () {
                setState(() {
                  _voiceMode = !_voiceMode;
                  if (_voiceMode) {
                    _startListening();
                  } else {
                    _stopListening();
                  }
                });
              },
            ),
          // 연속 촬영 모드 토글
          IconButton(
            icon: Icon(
              _batchMode ? Icons.burst_mode : Icons.burst_mode_outlined,
              color: _batchMode ? Colors.amber : Colors.white,
            ),
            tooltip: '연속 촬영 모드',
            onPressed: () {
              setState(() {
                _batchMode = !_batchMode;
                if (!_batchMode) {
                  _smartBatchCaptureCount = 0;
                  _detectedMultiDocs = null;
                }
              });
            },
          ),
          if (_batchMode && _batchImages.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.check, color: Colors.green),
              label: Text(
                '완료 (${_batchImages.length}장)',
                style: const TextStyle(color: Colors.green),
              ),
              onPressed: _finishBatch,
            ),
        ],
      ),
      body: Column(
        children: [
          // 카메라 미리보기 영역
          Expanded(
            child: _isCameraAvailable && _isCameraInitialized
                ? _buildCameraPreview()
                : _buildNoCameraView(),
          ),
          // 배치 모드 미리보기
          if (_batchMode && _batchImages.isNotEmpty) _buildBatchPreview(),
          // 하단 컨트롤
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 카메라 프리뷰
        Center(
          child: CameraPreview(_cameraController!),
        ),

        // vFlat 스타일: 실시간 감지된 문서 경계선
        if (_autoMode && _detectedCorners != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _DetectedDocumentPainter(
                corners: _detectedCorners!,
                quality: _qualityInfo,
              ),
            ),
          ),

        // 스마트 배치: 추가 문서 경계선 (다중 감지)
        if (_batchMode && _detectedMultiDocs != null)
          for (int i = 1; i < _detectedMultiDocs!.length; i++)
            Positioned.fill(
              child: CustomPaint(
                painter: _DetectedDocumentPainter(
                  corners: _detectedMultiDocs![i],
                  quality: null,
                  overrideColor: _multiDocColor(i),
                ),
              ),
            ),

        // 가이드 오버레이 (자동 모드가 아닐 때만)
        if (!_autoMode)
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanGuideOverlayPainter(),
            ),
          ),

        // vFlat 스타일: 품질 점수 및 이슈 표시
        if (_autoMode && _qualityInfo != null)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: _buildQualityIndicator(),
          ),

        // 스마트 배치: 다중 문서 감지 안내
        if (_batchMode &&
            _autoMode &&
            _detectedMultiDocs != null &&
            _detectedMultiDocs!.length > 1)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '문서 ${_detectedMultiDocs!.length}개 감지됨',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),

        // vFlat 스타일: 자동 촬영 카운트다운
        if (_autoCountdown > 0)
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$_autoCountdown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

        // 스마트 배치: 촬영 완료 피드백
        if (_showCapturedFeedback)
          Center(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check, color: Colors.white, size: 64),
                  const SizedBox(height: 4),
                  Text(
                    '${_batchImages.length}장 촬영',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 다중 문서 경계선 색상
  Color _multiDocColor(int index) {
    const colors = [Colors.cyan, Colors.purple, Colors.amber, Colors.pink];
    return colors[index % colors.length];
  }

  /// vFlat 스타일: 품질 표시 위젯
  Widget _buildQualityIndicator() {
    final quality = _qualityInfo!;
    final score = quality['score'] as double;
    final isGood = quality['isGood'] as bool;
    final issues = quality['issues'] as List<String>;

    Color indicatorColor;
    IconData indicatorIcon;
    String statusText;

    if (isGood) {
      indicatorColor = Colors.green;
      indicatorIcon = Icons.check_circle;
      statusText = '촬영 준비 완료';
    } else if (score >= 50) {
      indicatorColor = Colors.orange;
      indicatorIcon = Icons.warning;
      statusText = '품질 개선 필요';
    } else {
      indicatorColor = Colors.red;
      indicatorIcon = Icons.error;
      statusText = '문서를 찾을 수 없음';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(indicatorIcon, color: indicatorColor, size: 24),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: indicatorColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${score.toInt()}%',
                style: TextStyle(
                  color: indicatorColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...issues.map((issue) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        issue,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          // vFlat 초월: 문서 크기 표시
          if (_documentSize != null && _documentSize!.detectedSize != PaperSize.unknown) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white30, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.straighten, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  _documentSize!.toString(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoCameraView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_outlined,
            size: 80,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '카메라를 사용할 수 없습니다',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '카메라 권한을 확인하거나 아래 버튼으로\n이미지 파일을 선택해주세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  // 카메라 재시도
                  await _initCamera();
                },
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text('다시 시도', style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  // 앱 설정 열기 (permission_handler 없이 직접 intent)
                  try {
                    // ignore: deprecated_member_use
                    await _cameraController?.dispose();
                    _cameraController = null;
                  } catch (_) {}
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('시스템 설정에서 카메라 권한을 허용해주세요'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.settings, color: Colors.white70),
                label: const Text('권한 확인', style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchPreview() {
    return Container(
      height: 80,
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _batchImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_batchImages[index]),
                    width: 60,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                // 페이지 번호
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                // 삭제 버튼
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _batchImages.removeAt(index));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Colors.black,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 파일에서 선택
            _buildControlButton(
              icon: Icons.photo_library,
              label: '파일 선택',
              onTap: _pickFromFile,
            ),
            // 촬영 버튼 (카메라 있을 때만)
            if (_isCameraAvailable && _isCameraInitialized)
              GestureDetector(
                onTap: _isCapturing ? null : _captureImage,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCapturing ? Colors.grey : Colors.white,
                    border: Border.all(color: Colors.white30, width: 4),
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black54,
                          ),
                        )
                      : const Icon(Icons.camera, size: 36, color: Colors.black),
                ),
              ),
            // 갤러리에서 선택
            _buildControlButton(
              icon: Icons.image,
              label: '갤러리',
              onTap: _pickFromGallery,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 스캔 가이드 오버레이 (카메라 위에 표시)
class _ScanGuideOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 문서 가이드 사각형 (화면 중앙 80%)
    final margin = size.width * 0.08;
    final rect = Rect.fromLTRB(
      margin,
      size.height * 0.05,
      size.width - margin,
      size.height * 0.95,
    );

    // 모서리에만 L자 표시
    final cornerLen = 30.0;

    // 좌상
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLen, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLen), paint);
    // 우상
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-cornerLen, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, cornerLen), paint);
    // 우하
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + Offset(-cornerLen, 0), paint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight + Offset(0, -cornerLen), paint);
    // 좌하
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(cornerLen, 0), paint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(0, -cornerLen), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// vFlat 스타일: 실시간 감지된 문서 경계선 그리기
class _DetectedDocumentPainter extends CustomPainter {
  final List<Offset> corners;
  final Map<String, dynamic>? quality;
  final Color? overrideColor; // 사용자 지정 색상 (스마트 배치용)

  _DetectedDocumentPainter({
    required this.corners,
    this.quality,
    this.overrideColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    // 품질에 따라 색상 결정 (사용자 지정 색상이 있으면 그것 사용)
    Color lineColor;
    if (overrideColor != null) {
      lineColor = overrideColor!;
    } else if (quality != null && quality!['isGood'] == true) {
      lineColor = Colors.green; // 좋은 품질: 초록색
    } else if (quality != null && quality!['score'] >= 50) {
      lineColor = Colors.orange; // 중간 품질: 주황색
    } else {
      lineColor = Colors.red; // 나쁜 품질: 빨간색
    }

    // 픽셀 좌표로 변환
    final points = corners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();

    final docPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // 반투명 마스크 (문서 외부 영역) - 주 문서만 표시
    if (overrideColor == null) {
      final maskPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      final fullPath = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

      final maskPath =
          Path.combine(PathOperation.difference, fullPath, docPath);

      canvas.drawPath(maskPath, maskPaint);
    }

    // 문서 경계선 (두껍고 선명하게)
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    canvas.drawPath(docPath, linePaint);

    // 모서리 핸들 (vFlat 스타일)
    final handlePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (final point in points) {
      // 외곽 원
      canvas.drawCircle(
        point,
        12,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      // 내부 원
      canvas.drawCircle(point, 8, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_DetectedDocumentPainter oldDelegate) {
    return corners != oldDelegate.corners ||
        quality != oldDelegate.quality ||
        overrideColor != oldDelegate.overrideColor;
  }
}

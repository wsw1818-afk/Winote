import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;

/// DocAligner(ONNX) 기반 문서/책 4꼭짓점 감지 서비스
/// 모델: doc_aligner_book_v2_int8.onnx (2.17MB) — INT8 양자화, 바인더 노트 포함 합성 데이터 7,000장으로 fine-tuned
/// 입력: [1, 3, 256, 256] float32 (RGB, NCHW, 0~1 정규화)
/// 출력: points [1, 8] (TL/TR/BR/BL x,y 정규화 좌표), has_obj [1, 1] (문서 확률)

/// DocAligner 감지 결과 (코너 + 신뢰도)
class DocAlignerResult {
  final List<Offset> corners; // [TL, TR, BR, BL] 정규화 좌표 (0~1)
  final double confidence;    // has_obj 값 (0~1)
  const DocAlignerResult(this.corners, this.confidence);
}

class DocAlignerService {
  DocAlignerService._();
  static final DocAlignerService instance = DocAlignerService._();

  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _initialized = false;

  static const String _modelAsset =
      'assets/models/doc_aligner_book_v2.onnx';
  static const int _inputSize = 256;
  static const double _hasObjThreshold = 0.5;

  /// 모델 초기화 (첫 사용 시 자동 호출)
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      OrtEnv.instance.init();
      _sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(2)
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      final rawAsset = await rootBundle.load(_modelAsset);
      final bytes = rawAsset.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      debugPrint('[DocAligner] 모델 로드 완료 (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      // _initialized를 true로 유지 → 매 프레임 재시도 방지 (session == null이면 추론 스킵)
      debugPrint('[DocAligner] 모델 로드 실패: $e');
    }
  }

  /// 이미지 bytes(JPEG/PNG)에서 4꼭짓점 감지
  /// 반환: [TL, TR, BR, BL] 픽셀 좌표, 감지 실패 시 null
  Future<List<Offset>?> detectCorners(Uint8List imageBytes) async {
    if (!_initialized) await init();
    if (_session == null) return null;

    try {
      // 1) 이미지 디코드
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;
      final origW = decoded.width.toDouble();
      final origH = decoded.height.toDouble();

      // 2) 256x256 리사이즈
      final resized = img.copyResize(decoded,
          width: _inputSize,
          height: _inputSize,
          interpolation: img.Interpolation.linear);

      // 3) NCHW float32 [0,1] 변환 (RGB 채널 순서)
      final inputData = Float32List(_inputSize * _inputSize * 3);
      final planeSize = _inputSize * _inputSize;
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final idx = y * _inputSize + x;
          inputData[idx] = pixel.r / 255.0;
          inputData[planeSize + idx] = pixel.g / 255.0;
          inputData[planeSize * 2 + idx] = pixel.b / 255.0;
        }
      }

      // 4) 추론
      final inputTensor = OrtValueTensor.createTensorWithDataList(
          inputData, [1, 3, _inputSize, _inputSize]);
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(
          runOptions, {'img': inputTensor});
      inputTensor.release();
      runOptions.release();

      if (outputs == null) return null;

      // 5) 결과 파싱
      // has_obj: [1, 1] float
      final hasObjVal = outputs[1]?.value;
      final hasObj = hasObjVal is List
          ? ((hasObjVal[0] is List) ? (hasObjVal[0][0] as double) : (hasObjVal[0] as double))
          : 0.0;

      for (final o in outputs) { o?.release(); }

      debugPrint('[DocAligner] has_obj: ${hasObj.toStringAsFixed(3)}');
      if (hasObj < _hasObjThreshold) {
        debugPrint('[DocAligner] 문서 미감지 (has_obj < $_hasObjThreshold)');
        return null;
      }

      // points: [1, 8] float → [x1,y1, x2,y2, x3,y3, x4,y4]
      final pointsVal = outputs[0]?.value;
      List<double> points;
      if (pointsVal is List) {
        final inner = pointsVal[0];
        if (inner is List) {
          points = inner.map((v) => (v as num).toDouble()).toList();
        } else {
          points = [for (final v in pointsVal) (v as num).toDouble()];
        }
      } else {
        return null;
      }

      // 6) 정규화 좌표 → 원본 픽셀 좌표
      final corners = <Offset>[];
      for (int i = 0; i < 4; i++) {
        corners.add(Offset(points[i * 2] * origW, points[i * 2 + 1] * origH));
      }

      debugPrint('[DocAligner] 성공: ${corners.map((p) => '(${(p.dx / origW).toStringAsFixed(2)},${(p.dy / origH).toStringAsFixed(2)})').join(' ')}');
      return corners; // [TL, TR, BR, BL]
    } catch (e, st) {
      debugPrint('[DocAligner] 추론 오류: $e\n$st');
      return null;
    }
  }

  /// 카메라 Y plane(그레이스케일)에서 4꼭짓점 감지 (실시간 자동 스캔용)
  /// YUV420의 Y plane만으로 추론 (그레이스케일 → R=G=B로 변환)
  /// 반환: DocAlignerResult (코너 + confidence), 감지 실패 시 null
  Future<DocAlignerResult?> detectCornersFromYPlane(
    Uint8List yBytes, int srcWidth, int srcHeight, int bytesPerRow,
    {bool needsRotation = false}
  ) async {
    if (!_initialized) await init();
    if (_session == null) return null;

    try {
      // 1) Y plane → 256x256 리사이즈 + NCHW float32 변환 (최적화: 1채널 계산 후 복사)
      //    센서 회전 처리: needsRotation이면 90도 시계방향 회전
      const planeSize = _inputSize * _inputSize;
      final inputData = Float32List(planeSize * 3);

      final int effectiveW = needsRotation ? srcHeight : srcWidth;
      final int effectiveH = needsRotation ? srcWidth : srcHeight;

      // 스케일 계수 사전 계산 (루프 내 나눗셈 제거)
      final double scaleX = effectiveW / _inputSize;
      final double scaleY = effectiveH / _inputSize;
      final int maxSrcX = effectiveW - 1;
      final int maxSrcY = effectiveH - 1;
      final int yLen = yBytes.length;
      final int srcHm1 = srcHeight - 1;

      // 1채널(그레이스케일)만 먼저 계산
      for (int y = 0; y < _inputSize; y++) {
        final int baseSrcY = (y * scaleY).toInt().clamp(0, maxSrcY);
        for (int x = 0; x < _inputSize; x++) {
          final int baseSrcX = (x * scaleX).toInt().clamp(0, maxSrcX);

          // 회전 처리
          int rawX, rawY;
          if (needsRotation) {
            rawX = srcHm1 - baseSrcY;
            rawY = baseSrcX;
          } else {
            rawX = baseSrcX;
            rawY = baseSrcY;
          }

          final idx = rawY * bytesPerRow + rawX;
          final val = (idx >= 0 && idx < yLen) ? yBytes[idx] / 255.0 : 0.0;
          inputData[y * _inputSize + x] = val;
        }
      }

      // R=G=B (그레이스케일): 1채널 데이터를 G, B 채널에 복사
      inputData.setRange(planeSize, planeSize * 2, inputData, 0);
      inputData.setRange(planeSize * 2, planeSize * 3, inputData, 0);

      // 2) 추론
      final inputTensor = OrtValueTensor.createTensorWithDataList(
          inputData, [1, 3, _inputSize, _inputSize]);
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(
          runOptions, {'img': inputTensor});
      inputTensor.release();
      runOptions.release();

      if (outputs == null) return null;

      // 3) has_obj 확인
      final hasObjVal = outputs[1]?.value;
      final hasObj = hasObjVal is List
          ? ((hasObjVal[0] is List) ? (hasObjVal[0][0] as double) : (hasObjVal[0] as double))
          : 0.0;

      if (hasObj < _hasObjThreshold) {
        for (final o in outputs) { o?.release(); }
        return null;
      }

      // 4) points 파싱 → 정규화 좌표 (0~1)
      final pointsVal = outputs[0]?.value;
      List<double> points;
      if (pointsVal is List) {
        final inner = pointsVal[0];
        if (inner is List) {
          points = inner.map((v) => (v as num).toDouble()).toList();
        } else {
          points = [for (final v in pointsVal) (v as num).toDouble()];
        }
      } else {
        for (final o in outputs) { o?.release(); }
        return null;
      }

      for (final o in outputs) { o?.release(); }

      // 정규화 좌표 그대로 반환 (0~1) + confidence
      final corners = <Offset>[];
      for (int i = 0; i < 4; i++) {
        corners.add(Offset(
          points[i * 2].clamp(0.0, 1.0),
          points[i * 2 + 1].clamp(0.0, 1.0),
        ));
      }

      return DocAlignerResult(corners, hasObj); // 코너 + 신뢰도
    } catch (e) {
      debugPrint('[DocAligner] Y plane 추론 오류: $e');
      return null;
    }
  }

  void dispose() {
    _session?.release();
    _sessionOptions?.release();
    _session = null;
    _sessionOptions = null;
    _initialized = false;
    OrtEnv.instance.release();
  }
}

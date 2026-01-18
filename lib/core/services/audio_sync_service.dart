import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/stroke.dart';

/// 녹음 상태
enum RecordingState {
  idle,       // 대기
  recording,  // 녹음 중
  paused,     // 일시정지
  playing,    // 재생 중
}

/// 타임스탬프가 있는 스트로크 데이터
class TimestampedStroke {
  final Stroke stroke;
  final int recordingStartTime; // 녹음 시작 기준 오프셋 (ms)
  final int recordingEndTime;   // 스트로크 완료 시점 (ms)

  TimestampedStroke({
    required this.stroke,
    required this.recordingStartTime,
    required this.recordingEndTime,
  });

  Map<String, dynamic> toJson() => {
    'stroke': stroke.toJson(),
    'recordingStartTime': recordingStartTime,
    'recordingEndTime': recordingEndTime,
  };

  factory TimestampedStroke.fromJson(Map<String, dynamic> json) {
    return TimestampedStroke(
      stroke: Stroke.fromJson(json['stroke'] as Map<String, dynamic>),
      recordingStartTime: json['recordingStartTime'] as int,
      recordingEndTime: json['recordingEndTime'] as int,
    );
  }
}

/// 녹음 세션 정보
class RecordingSession {
  final String id;
  final String noteId;
  final String? audioFilePath;
  final DateTime startTime;
  final int durationMs;
  final List<TimestampedStroke> strokes;

  RecordingSession({
    required this.id,
    required this.noteId,
    this.audioFilePath,
    required this.startTime,
    required this.durationMs,
    required this.strokes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'noteId': noteId,
    'audioFilePath': audioFilePath,
    'startTime': startTime.toIso8601String(),
    'durationMs': durationMs,
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      audioFilePath: json['audioFilePath'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      durationMs: json['durationMs'] as int,
      strokes: (json['strokes'] as List<dynamic>)
          .map((s) => TimestampedStroke.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  RecordingSession copyWith({
    String? id,
    String? noteId,
    String? audioFilePath,
    DateTime? startTime,
    int? durationMs,
    List<TimestampedStroke>? strokes,
  }) {
    return RecordingSession(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      startTime: startTime ?? this.startTime,
      durationMs: durationMs ?? this.durationMs,
      strokes: strokes ?? this.strokes,
    );
  }
}

/// 녹음-필기 동기화 서비스
/// 녹음 중 작성된 필기를 타임스탬프와 함께 저장하고,
/// 재생 시 해당 시점의 필기를 하이라이트합니다.
class AudioSyncService {
  static AudioSyncService? _instance;
  static AudioSyncService get instance {
    _instance ??= AudioSyncService._();
    return _instance!;
  }

  AudioSyncService._();

  // 상태
  RecordingState _state = RecordingState.idle;
  RecordingSession? _currentSession;
  DateTime? _recordingStartTime;
  final List<TimestampedStroke> _pendingStrokes = [];

  // 재생 관련
  int _currentPlaybackTime = 0; // 현재 재생 위치 (ms)
  List<Stroke> _visibleStrokes = []; // 현재 재생 위치까지 보여줄 스트로크

  // Getters
  RecordingState get state => _state;
  RecordingSession? get currentSession => _currentSession;
  bool get isRecording => _state == RecordingState.recording;
  bool get isPlaying => _state == RecordingState.playing;
  int get currentPlaybackTime => _currentPlaybackTime;
  List<Stroke> get visibleStrokes => _visibleStrokes;

  // 콜백
  void Function(RecordingState state)? onStateChanged;
  void Function(int timeMs, List<Stroke> strokes)? onPlaybackUpdate;

  /// 녹음 시작
  Future<bool> startRecording(String noteId) async {
    if (_state != RecordingState.idle) {
      debugPrint('[AudioSync] Already recording');
      return false;
    }

    try {
      _recordingStartTime = DateTime.now();
      _pendingStrokes.clear();

      final sessionId = 'rec_${DateTime.now().millisecondsSinceEpoch}';

      _currentSession = RecordingSession(
        id: sessionId,
        noteId: noteId,
        startTime: _recordingStartTime!,
        durationMs: 0,
        strokes: [],
      );

      _state = RecordingState.recording;
      onStateChanged?.call(_state);

      // TODO: 실제 오디오 녹음 시작
      // - Windows: 마이크 입력 캡처
      // - record 패키지 또는 Platform Channel 사용

      debugPrint('[AudioSync] Recording started: $sessionId');
      return true;
    } catch (e) {
      debugPrint('[AudioSync] Error starting recording: $e');
      return false;
    }
  }

  /// 녹음 중 스트로크 추가
  void addStrokeDuringRecording(Stroke stroke) {
    if (!isRecording || _recordingStartTime == null) return;

    final now = DateTime.now();
    final startOffset = now.difference(_recordingStartTime!).inMilliseconds;

    _pendingStrokes.add(TimestampedStroke(
      stroke: stroke,
      recordingStartTime: startOffset,
      recordingEndTime: startOffset, // 단순화: 시작=종료
    ));

    debugPrint('[AudioSync] Stroke added at ${startOffset}ms');
  }

  /// 녹음 일시정지
  void pauseRecording() {
    if (_state != RecordingState.recording) return;

    _state = RecordingState.paused;
    onStateChanged?.call(_state);

    debugPrint('[AudioSync] Recording paused');
  }

  /// 녹음 재개
  void resumeRecording() {
    if (_state != RecordingState.paused) return;

    _state = RecordingState.recording;
    onStateChanged?.call(_state);

    debugPrint('[AudioSync] Recording resumed');
  }

  /// 녹음 중지 및 저장
  Future<RecordingSession?> stopRecording() async {
    if (_state != RecordingState.recording && _state != RecordingState.paused) {
      return null;
    }

    try {
      final endTime = DateTime.now();
      final duration = endTime.difference(_recordingStartTime!).inMilliseconds;

      // 세션 업데이트
      _currentSession = _currentSession?.copyWith(
        durationMs: duration,
        strokes: List.from(_pendingStrokes),
      );

      // 세션 파일 저장
      if (_currentSession != null) {
        await _saveSession(_currentSession!);
      }

      final session = _currentSession;

      // 상태 초기화
      _state = RecordingState.idle;
      _recordingStartTime = null;
      _pendingStrokes.clear();
      _currentSession = null;

      onStateChanged?.call(_state);

      debugPrint('[AudioSync] Recording stopped, duration: ${duration}ms, strokes: ${session?.strokes.length}');
      return session;
    } catch (e) {
      debugPrint('[AudioSync] Error stopping recording: $e');
      return null;
    }
  }

  /// 세션 저장
  Future<void> _saveSession(RecordingSession session) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sessionsDir = Directory(
        '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}recordings',
      );

      if (!await sessionsDir.exists()) {
        await sessionsDir.create(recursive: true);
      }

      final filePath = '${sessionsDir.path}${Platform.pathSeparator}${session.id}.json';
      final file = File(filePath);

      await file.writeAsString(session.toJson().toString());

      debugPrint('[AudioSync] Session saved: $filePath');
    } catch (e) {
      debugPrint('[AudioSync] Error saving session: $e');
    }
  }

  /// 노트의 녹음 세션 목록 조회
  Future<List<RecordingSession>> getSessionsForNote(String noteId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sessionsDir = Directory(
        '${appDir.path}${Platform.pathSeparator}Winote${Platform.pathSeparator}recordings',
      );

      if (!await sessionsDir.exists()) {
        return [];
      }

      final sessions = <RecordingSession>[];

      await for (final entity in sessionsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            // TODO: 실제 JSON 파싱
            // final session = RecordingSession.fromJson(jsonDecode(content));
            // if (session.noteId == noteId) {
            //   sessions.add(session);
            // }
          } catch (e) {
            debugPrint('[AudioSync] Error reading session: $e');
          }
        }
      }

      return sessions;
    } catch (e) {
      debugPrint('[AudioSync] Error listing sessions: $e');
      return [];
    }
  }

  /// 녹음 재생 시작
  Future<void> startPlayback(RecordingSession session) async {
    if (_state != RecordingState.idle) {
      debugPrint('[AudioSync] Cannot start playback while recording');
      return;
    }

    _currentSession = session;
    _currentPlaybackTime = 0;
    _visibleStrokes = [];
    _state = RecordingState.playing;

    onStateChanged?.call(_state);

    // TODO: 실제 오디오 재생 시작
    // - audioplayers 패키지 또는 Platform Channel 사용

    debugPrint('[AudioSync] Playback started: ${session.id}');
  }

  /// 재생 위치 업데이트 (외부에서 호출)
  void updatePlaybackPosition(int timeMs) {
    if (!isPlaying || _currentSession == null) return;

    _currentPlaybackTime = timeMs;

    // 현재 시간까지의 스트로크만 표시
    _visibleStrokes = _currentSession!.strokes
        .where((ts) => ts.recordingStartTime <= timeMs)
        .map((ts) => ts.stroke)
        .toList();

    onPlaybackUpdate?.call(timeMs, _visibleStrokes);
  }

  /// 재생 중지
  void stopPlayback() {
    if (!isPlaying) return;

    _state = RecordingState.idle;
    _currentSession = null;
    _currentPlaybackTime = 0;
    _visibleStrokes = [];

    onStateChanged?.call(_state);

    debugPrint('[AudioSync] Playback stopped');
  }

  /// 특정 시간대의 스트로크 가져오기
  List<Stroke> getStrokesAtTime(RecordingSession session, int timeMs) {
    return session.strokes
        .where((ts) => ts.recordingStartTime <= timeMs)
        .map((ts) => ts.stroke)
        .toList();
  }

  /// 특정 시간대의 스트로크 하이라이트 (애니메이션용)
  List<Stroke> getStrokesInRange(
    RecordingSession session,
    int startMs,
    int endMs,
  ) {
    return session.strokes
        .where((ts) =>
            ts.recordingStartTime >= startMs && ts.recordingStartTime <= endMs)
        .map((ts) => ts.stroke)
        .toList();
  }

  /// 녹음 시간 포맷
  String formatDuration(int ms) {
    final seconds = (ms / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// Stroke 확장 (JSON 직렬화)
extension StrokeJson on Stroke {
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'toolType': toolType.index,
      'color': color.value,
      'width': width,
      'points': points.map((p) => {
        'x': p.x,
        'y': p.y,
        'pressure': p.pressure,
        'tilt': p.tilt,
        'timestamp': p.timestamp,
      }).toList(),
      'timestamp': timestamp,
      'isShape': isShape,
      'shapeType': shapeType.index,
    };
  }

  static Stroke fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      toolType: ToolType.values[json['toolType'] as int],
      color: Color(json['color'] as int),
      width: (json['width'] as num).toDouble(),
      points: (json['points'] as List<dynamic>).map((p) {
        final map = p as Map<String, dynamic>;
        return StrokePoint(
          x: (map['x'] as num).toDouble(),
          y: (map['y'] as num).toDouble(),
          pressure: (map['pressure'] as num).toDouble(),
          tilt: (map['tilt'] as num).toDouble(),
          timestamp: map['timestamp'] as int,
        );
      }).toList(),
      timestamp: json['timestamp'] as int,
      isShape: json['isShape'] as bool? ?? false,
      shapeType: ShapeType.values[json['shapeType'] as int? ?? 0],
    );
  }
}

// stroke_point.dart에서 가져와야 하지만, 여기서는 간단히 정의
class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final double tilt;
  final int timestamp;

  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tilt,
    required this.timestamp,
  });
}

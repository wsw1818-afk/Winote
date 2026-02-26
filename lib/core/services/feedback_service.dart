import 'package:flutter/material.dart';

/// 피드백 메시지 타입
enum FeedbackType {
  success,   // 성공 (초록색)
  error,     // 오류 (빨간색)
  warning,   // 경고 (주황색)
  info,      // 정보 (파란색)
}

/// 피드백 메시지 데이터
class FeedbackMessage {
  final String message;
  final FeedbackType type;
  final DateTime timestamp;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  FeedbackMessage({
    required this.message,
    required this.type,
    DateTime? timestamp,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 사용자 피드백 서비스 (Snackbar/Toast 관리)
class FeedbackService {
  static FeedbackService? _instance;
  static FeedbackService get instance {
    _instance ??= FeedbackService._();
    return _instance!;
  }

  FeedbackService._();

  // 최근 피드백 이력 (디버깅/로깅용)
  final List<FeedbackMessage> _recentFeedbacks = [];
  static const int _maxRecentFeedbacks = 50;

  // 현재 표시 중인 ScaffoldMessengerState
  GlobalKey<ScaffoldMessengerState>? _messengerKey;

  /// ScaffoldMessenger 키 설정 (앱 시작 시 호출)
  void setMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _messengerKey = key;
  }

  /// 최근 피드백 이력 가져오기
  List<FeedbackMessage> get recentFeedbacks => List.unmodifiable(_recentFeedbacks);

  /// 성공 메시지 표시
  void showSuccess(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showFeedback(
      context,
      FeedbackMessage(
        message: message,
        type: FeedbackType.success,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
  }

  /// 오류 메시지 표시
  void showError(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    _showFeedback(
      context,
      FeedbackMessage(
        message: message,
        type: FeedbackType.error,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
  }

  /// 경고 메시지 표시
  void showWarning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    _showFeedback(
      context,
      FeedbackMessage(
        message: message,
        type: FeedbackType.warning,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
  }

  /// 정보 메시지 표시
  void showInfo(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showFeedback(
      context,
      FeedbackMessage(
        message: message,
        type: FeedbackType.info,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
  }

  /// 저장 성공 메시지
  void showSaveSuccess(BuildContext context, {String? title}) {
    showSuccess(
      context,
      title != null ? '"$title" 저장됨' : '저장 완료',
      duration: const Duration(seconds: 2),
    );
  }

  /// 저장 실패 메시지
  void showSaveError(BuildContext context, {String? error}) {
    showError(
      context,
      '저장 실패${error != null ? ': $error' : ''}',
      actionLabel: '다시 시도',
      duration: const Duration(seconds: 5),
    );
  }

  /// 내보내기 성공 메시지
  void showExportSuccess(BuildContext context, String filePath, {VoidCallback? onOpen}) {
    showSuccess(
      context,
      '파일 내보내기 완료',
      actionLabel: onOpen != null ? '열기' : null,
      onAction: onOpen,
      duration: const Duration(seconds: 4),
    );
  }

  /// 내보내기 실패 메시지
  void showExportError(BuildContext context, {String? error}) {
    showError(
      context,
      '내보내기 실패${error != null ? ': $error' : ''}',
      duration: const Duration(seconds: 5),
    );
  }

  /// 클립보드 복사 성공
  void showCopySuccess(BuildContext context) {
    showSuccess(
      context,
      '클립보드에 복사됨',
      duration: const Duration(seconds: 2),
    );
  }

  /// 삭제 완료 메시지 (Undo 액션 포함)
  void showDeleteSuccess(
    BuildContext context,
    String itemName, {
    VoidCallback? onUndo,
  }) {
    showInfo(
      context,
      '"$itemName" 삭제됨',
      actionLabel: onUndo != null ? '실행취소' : null,
      onAction: onUndo,
      duration: const Duration(seconds: 5),
    );
  }

  /// 네트워크 오류 메시지
  void showNetworkError(BuildContext context, {VoidCallback? onRetry}) {
    showError(
      context,
      '네트워크 연결을 확인해주세요',
      actionLabel: onRetry != null ? '재시도' : null,
      onAction: onRetry,
      duration: const Duration(seconds: 5),
    );
  }

  /// 동기화 상태 메시지
  void showSyncStatus(BuildContext context, bool success, {String? message}) {
    if (success) {
      showSuccess(
        context,
        message ?? '동기화 완료',
        duration: const Duration(seconds: 2),
      );
    } else {
      showWarning(
        context,
        message ?? '동기화 실패. 나중에 다시 시도합니다.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// 실행취소 완료 메시지
  void showUndoComplete(BuildContext context) {
    showInfo(
      context,
      '실행취소 완료',
      duration: const Duration(seconds: 2),
    );
  }

  /// 다시실행 완료 메시지
  void showRedoComplete(BuildContext context) {
    showInfo(
      context,
      '다시실행 완료',
      duration: const Duration(seconds: 2),
    );
  }

  /// 피드백 메시지 표시 (내부 메서드)
  void _showFeedback(BuildContext context, FeedbackMessage feedback) {
    // 이력에 추가
    _recentFeedbacks.insert(0, feedback);
    if (_recentFeedbacks.length > _maxRecentFeedbacks) {
      _recentFeedbacks.removeLast();
    }

    // Snackbar 표시
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            _getIcon(feedback.type),
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feedback.message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: _getBackgroundColor(feedback.type),
      duration: feedback.duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      action: feedback.actionLabel != null
          ? SnackBarAction(
              label: feedback.actionLabel!,
              textColor: Colors.white,
              onPressed: () {
                feedback.onAction?.call();
              },
            )
          : null,
    );

    // 기존 Snackbar 제거 후 새로 표시
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  /// 타입별 아이콘 반환
  IconData _getIcon(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return Icons.check_circle;
      case FeedbackType.error:
        return Icons.error;
      case FeedbackType.warning:
        return Icons.warning;
      case FeedbackType.info:
        return Icons.info;
    }
  }

  /// 타입별 배경색 반환
  Color _getBackgroundColor(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return const Color(0xFF4CAF50); // 초록
      case FeedbackType.error:
        return const Color(0xFFE53935); // 빨강
      case FeedbackType.warning:
        return const Color(0xFFFF9800); // 주황
      case FeedbackType.info:
        return const Color(0xFF2196F3); // 파랑
    }
  }

  /// 모든 피드백 이력 초기화
  void clearHistory() {
    _recentFeedbacks.clear();
  }
}

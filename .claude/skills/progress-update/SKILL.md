---
name: progress-update
description: Updates PROGRESS.md with current work status and .commit_message.txt with latest change description. Use when finishing a task, completing a feature, or when the user says "진행 업데이트", "progress", or "마무리".
disable-model-invocation: true
---

# 진행 상황 업데이트

PROGRESS.md와 .commit_message.txt를 현재 작업 상태로 갱신합니다.

## 실행 순서

1. **PROGRESS.md 읽기** — 현재 내용 확인
2. **이번 세션 작업 내용 정리** — 완료한 것, 변경한 파일, 남은 이슈
3. **PROGRESS.md 업데이트** — 아래 형식으로 갱신

### PROGRESS.md 업데이트 형식

```markdown
## Dashboard
- Progress: (진행률 %)
- Risk: (낮음/중간/높음)

## Today Goal
- (오늘의 목표)

## What changed (YYYY-MM-DD)
- (이번 작업에서 변경한 내용)

## Previous changes (YYYY-MM-DD)
- (이전 What changed 내용을 여기로 이동)

## Open issues
- (발견된 이슈나 차단 사항)

## Next
1) (다음에 할 일)
2) (다음에 할 일)
3) (다음에 할 일)
```

4. **.commit_message.txt 업데이트** — 이모지 포함 한국어 한 줄로 덮어쓰기
   - 먼저 Read로 읽은 후 Edit으로 수정
   - 예: `✨ 검색 기능 추가: q 파라미터로 서버 필터링 구현`

## 아카이브 트리거 확인
- PROGRESS.md가 **5KB 초과** 또는 **완료 항목 20개 이상**이면:
  - 사용자에게 "PROGRESS.md가 커졌습니다. /archive로 아카이브할까요?" 안내

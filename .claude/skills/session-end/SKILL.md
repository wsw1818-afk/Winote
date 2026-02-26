---
name: session-end
description: Finalizes a work session by updating PROGRESS.md, .commit_message.txt, checking archive triggers, and outputting a session summary. Use when finishing work, or when the user says "끝", "마무리", "종료", or "done".
disable-model-invocation: true
---

# 세션 종료 워크플로우

작업 세션을 마무리하고 모든 진행 상황을 기록합니다.

## 실행 순서

1. **이번 세션 변경사항 수집**
   - git diff --stat (git 저장소인 경우)
   - 또는 세션 중 수정한 파일 목록 정리

2. **PROGRESS.md 업데이트**
   - Dashboard 진행률 갱신
   - What changed에 이번 세션 작업 내용 기록 (날짜 포함)
   - Open issues에 발견된 이슈 추가
   - Next에 다음 할 일 3가지 정리

3. **.commit_message.txt 갱신**
   - 먼저 Read로 읽은 후 Edit으로 수정
   - 이모지 포함 한국어 한 줄로 덮어쓰기

4. **아카이브 판단**
   - PROGRESS.md가 5KB 초과 또는 완료 항목 20개 이상이면:
   - "/archive로 아카이브할까요?" 안내

5. **MEMORY.md 제약사항 변경 확인**
   - 환경/버전/제약이 바뀌었으면 Constraints 섹션 갱신 안내

6. **세션 요약 출력**

```
## ✅ 세션 종료

### 이번 세션에서 한 일
- (완료 항목 3~5줄)

### 변경된 파일
- (파일 목록)

### 다음 세션에서 이어갈 일
1. ...
2. ...
3. ...

### 커밋 메시지
(commit_message.txt 내용)
```

## 주의사항
- `session-start`와 짝으로 사용 (시작 → 작업 → 종료)
- git revert 관련 작업이었으면 .commit_message.txt를 빈 파일로 만들기

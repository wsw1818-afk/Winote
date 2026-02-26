---
name: session-start
description: Initializes a new work session by loading CLAUDE.md, MEMORY.md, and PROGRESS.md in sequence. Use when starting a conversation, beginning work, or when the user says "시작", "작업 시작", or "start".
argument-hint: [project-path]
disable-model-invocation: true
---

# 세션 시작 워크플로우

새 작업 세션을 초기화합니다. 프로젝트 컨텍스트를 순서대로 로드합니다.

## 실행 순서

1. **CLAUDE.md 읽기** — 프로젝트 진입점, 라우터 규칙 확인
2. **MEMORY.md 읽기** — 프로젝트 목표, 기술 스택, 제약사항 파악
3. **PROGRESS.md 읽기** — 현재 진행 상황, 열린 이슈, 다음 할 일 확인
4. **.commit_message.txt 읽기** — 마지막 변경사항 확인

## 로드 후 출력

읽은 내용을 바탕으로 다음을 한국어로 요약 출력:

```
## 🚀 세션 시작

### 프로젝트 상태
- 목표: (MEMORY.md에서)
- 기술 스택: (MEMORY.md에서)

### 현재 진행
- (PROGRESS.md의 Open 항목들)

### 다음 할 일
- (PROGRESS.md의 Next 항목들)

### 마지막 변경
- (commit_message.txt 내용)
```

## 주의사항
- 파일이 없으면 빈 템플릿임을 안내하고 계속 진행
- AI_HYBRID_GUIDE.md는 필요할 때만 참조 (기본적으로 로드하지 않음)
- 사용자에게 "무엇을 도와드릴까요?" 로 마무리

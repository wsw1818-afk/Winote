---
name: handoff
description: Generates a concise handoff package for switching between AI models or sessions. Summarizes project context from MEMORY.md and PROGRESS.md into a copy-paste ready format. Use when switching models, saying "핸드오프", "모델 전환", or "handoff".
disable-model-invocation: true
---

# 핸드오프 패키지 생성

다른 AI 모델이나 새 세션으로 맥락을 전달하기 위한 핸드오프 패키지를 생성합니다.

## 수집 항목

1. **MEMORY.md** → 프로젝트 목표, 기술 스택, 제약사항
2. **PROGRESS.md** → 현재 진행 상황, 열린 이슈, 다음 할 일
3. **.commit_message.txt** → 마지막 변경사항
4. **AI_HYBRID_GUIDE.md** → 역할 분담 기준 (존재하는 경우)

## 핸드오프 패키지 출력 형식

```markdown
# 🔄 핸드오프 패키지
생성일: YYYY-MM-DD

## 프로젝트 요약
- **목표**: (MEMORY.md 1줄 요약)
- **기술 스택**: (MEMORY.md 요약)
- **주요 제약**: (MEMORY.md 요약)

## 현재 상태
- **진행률**: (PROGRESS.md Dashboard)
- **진행 중**: (Open 항목)
- **마지막 변경**: (.commit_message.txt)

## 열린 이슈
- (PROGRESS.md Issues 항목)

## 다음 할 일 (우선순위 순)
1. ...
2. ...
3. ...

## 핵심 파일 경로
- 메인 설정: CLAUDE.md → MEMORY.md → PROGRESS.md
- 규칙: .claude/rules/ (output-format, testing, security, error-handling)
- 스킬: .claude/skills/ (session-start, session-end, deploy 등)

## 역할 제안
- 이 작업에 적합한 역할: (설계/구현/리뷰/디버깅)
```

## 실행 전 자동 처리

- PROGRESS.md를 최신 상태로 갱신 후 패키지 생성
- 민감 정보(토큰, 비밀번호)는 마스킹
- 패키지는 **클립보드 복사 가능한 단일 텍스트 블록**으로 출력

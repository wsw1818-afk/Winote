# MEMORY.md — 프로젝트 규칙/기술 스택 (SSOT)

> 200줄 하드리밋. 넘으면 정리하거나 `.claude/rules/`로 분리.

## 1) Goal / Scope
- 목표: (프로젝트별로 채우기)
- 범위: (프로젝트별로 채우기)
- Non-goals: (프로젝트별로 채우기)

## 2) Tech Stack
- Framework:
- Language:
- State/Networking:
- Backend/DB:
- Build/CI:
- Target platforms:

## 3) Constraints
- OS/Node/Java/Gradle/SDK 버전:
- 빌드/배포 제약:
- 성능/번들 제약:
- 패키지 매니저: (pnpm-lock.yaml → pnpm, yarn.lock → yarn, package-lock.json → npm)

## 4) Coding Rules
- 최소 diff 원칙 (전체 재작성 금지)
- 테스트/수정 루프(최대 3회): lint → typecheck → test
- 비밀정보 금지: 값 금지(변수명/위치만 기록)
- 큰 변경(프레임워크/DB/상태관리 교체)은 사용자 확인 후 진행
- 한국어 진행 보고 (에러 원문/명령어/파일명은 원문 유지)

## 5) Architecture Notes
- 폴더 구조 요약:
- 주요 모듈 책임:
- 데이터 흐름:

## 6) Testing / Release Rules
- 통과 기준: lint + typecheck + test 모두 통과
- 릴리즈 체크리스트: (프로젝트별로 채우기)

## 7) File Organization (Claude Code 최적화)
- `CLAUDE.md`: 핵심 규칙만 (~40줄). 매 세션 로드됨
- `MEMORY.md`: 프로젝트 맥락/스택/제약. @import로 참조
- `PROGRESS.md`: 현재 진행/이슈. 5KB 초과 시 아카이브
- `.claude/rules/`: 주제별 규칙 (자동 로드, path-scoped 지원)
- `.claude/skills/`: 도메인별 워크플로우 (온디맨드 로드)
- `AI_HYBRID_GUIDE.md`: 하이브리드(멀티모델) 운영 전용

## 8) Known Risks
- (발견되면 추가)

# CLAUDE.md

IMPORTANT: 이 파일은 간결하게 유지한다. 상세 규칙은 `.claude/rules/`에 분리되어 자동 로드된다.

## Project Context
- 목표/스택/아키텍처: @MEMORY.md
- 현재 진행/이슈: @PROGRESS.md
- 과거 로그: `ARCHIVE_YYYY_MM.md`
- 하이브리드 운영(모델 간 핸드오프): @AI_HYBRID_GUIDE.md (필요시만)

## Workflow
- 작업 시작: CLAUDE.md → MEMORY.md → PROGRESS.md 순서로 읽기
- 작업 종료: PROGRESS.md 업데이트 + `.commit_message.txt` 업데이트
- PROGRESS가 5KB 초과 or 완료 항목 20개 → ARCHIVE로 이동

## Version Control
- 코드 변경 시 `.commit_message.txt`를 이모지 포함 한국어 한 줄로 덮어쓰기
- git revert 작업이면 빈 파일로 만들기
- YOU MUST: `.commit_message.txt`는 먼저 Read 후 Edit으로 수정

## Code Style
- 최소 diff 원칙 (전체 재작성 금지)
- 비밀정보(토큰/비밀번호/키) 코드/문서에 절대 금지 → `.env` 사용
- 모든 진행 설명은 한국어로 작성 (에러 원문/명령어/파일명은 원문 유지)

## Testing
- 변경 후 lint/typecheck/test 실행
- 실패 시 최소 수정 → 재실행 (최대 3회)
- 통과해야 완료로 간주

## Safety
- 큰 변경(프레임워크/DB/상태관리 교체)은 사용자 확인 후 진행
- NEVER: 비밀값을 문서/코드/예시에 포함
- ALWAYS: 변경 후 PROGRESS.md와 .commit_message.txt 갱신

## Compact Instructions
컨텍스트 압축 시 MEMORY.md의 Goal/Tech Stack/Constraints와 PROGRESS.md의 Open issues/Next를 우선 보존할 것

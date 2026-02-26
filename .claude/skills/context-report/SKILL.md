---
name: context-report
description: Generates a comprehensive project context report including file structure, tech stack, recent changes, and open issues. Use when the user asks for project overview, status report, or says "현황", "리포트", "report", or "프로젝트 상태".
disable-model-invocation: true
---

# 프로젝트 컨텍스트 리포트

현재 프로젝트의 종합적인 상태 리포트를 생성합니다.

## 수집 항목

### 1. 프로젝트 기본 정보
- MEMORY.md에서: 목표, 기술 스택, 제약사항
- CLAUDE.md에서: 핵심 규칙 요약

### 2. 파일 구조 요약
- 프로젝트 루트의 주요 파일/폴더 목록
- `.claude/rules/` 의 규칙 파일 목록
- `.claude/skills/` 의 스킬 파일 목록

### 3. 진행 상황
- PROGRESS.md에서: Open/Done/Issues/Next

### 4. 최근 변경
- .commit_message.txt 내용
- git log 최근 5개 (git 저장소인 경우)

### 5. 품질 지표
- lint/typecheck/test 상태 (실행 가능한 경우)

## 출력 형식

```markdown
# 📊 프로젝트 컨텍스트 리포트
생성일: YYYY-MM-DD

## 프로젝트 개요
- **목표**: ...
- **기술 스택**: ...
- **제약사항**: ...

## 파일 구조
(트리 형태)

## 현재 진행 상황
### 진행 중
- ...
### 완료
- ...
### 이슈
- ...

## 최근 변경 이력
| 날짜 | 내용 |
|------|------|

## 다음 할 일
1. ...
2. ...
3. ...
```

## 주의사항
- 리포트 생성은 **읽기 전용** — 파일 수정하지 않음
- 민감 정보(토큰, 비밀번호)는 마스킹
- 대용량 폴더(node_modules, android, ios)는 건너뜀

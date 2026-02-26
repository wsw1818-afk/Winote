---
name: project-init
description: Initializes a new project with CLAUDE.md, MEMORY.md, PROGRESS.md, .claude/rules/, and .claudeignore templates. Detects project type (Expo/RN, .NET WPF, Flutter, JS/TS) and pre-fills accordingly. Use when starting a new project or saying "프로젝트 초기화", "새 프로젝트", or "init".
disable-model-invocation: true
argument-hint: [project-type]
---

# 프로젝트 초기화 워크플로우

새 프로젝트에 Claude Code 환경을 세팅합니다.

## 1단계: 프로젝트 타입 감지/선택

파일 기반 자동 감지 또는 인자로 지정:

| 감지 파일 | 프로젝트 타입 |
|-----------|-------------|
| `app.json` + `expo` | Expo/React Native |
| `*.csproj` | .NET WPF |
| `pubspec.yaml` | Flutter |
| `package.json` (expo 없음) | 일반 JS/TS |
| `requirements.txt` / `pyproject.toml` | Python |

## 2단계: 기존 파일 확인

- 이미 CLAUDE.md가 있으면 **덮어쓰기 방지** → 병합 제안
- `.claude/rules/`가 있으면 기존 규칙 유지

## 3단계: 템플릿 파일 생성

### 필수 생성 파일
1. **CLAUDE.md** — 라우터 진입점 (~40줄)
2. **MEMORY.md** — 프로젝트 타입에 맞게 Tech Stack/Constraints 프리필
3. **PROGRESS.md** — 초기 템플릿
4. **.commit_message.txt** — 빈 파일

### 규칙 파일 (.claude/rules/)
5. **output-format.md** — 7섹션 출력 포맷
6. **testing.md** — 테스트/수정 루프 규칙
7. **security.md** — 보안 규칙
8. **error-handling.md** — 에러 대응 규칙

### 최적화 파일
9. **.claudeignore** — 프로젝트 타입별:
   - Expo/RN: `node_modules/`, `android/`, `ios/`, `.expo/`
   - .NET: `bin/`, `obj/`, `publish/`
   - Flutter: `build/`, `.dart_tool/`
   - 공통: `.git/`, `*.log`, `*.map`

## 4단계: 완료 안내

```
## 🎉 프로젝트 초기화 완료

생성된 파일:
- CLAUDE.md (진입점)
- MEMORY.md (프로젝트 맥락)
- PROGRESS.md (진행 관리)
- .claude/rules/ (4개 규칙)
- .claudeignore (성능 최적화)

다음 단계:
1. MEMORY.md에 프로젝트 목표/스택/제약 작성
2. /session-start로 세션 시작
```

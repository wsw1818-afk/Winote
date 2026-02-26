# 테스트/수정 루프 규칙

## 기본 루프 (최대 3회)
테스트 실행 → 실패 로그 인용 → 최소 수정 → 재실행

## 완료 조건
lint + typecheck + test 모두 통과 (또는 합리적 사유를 CHECKS에 기록)

## Flaky 테스트 대응
1. 환경변수/시계·랜덤/외부API 의존 여부 먼저 점검
2. 시드 고정(`--seed`) / 타임아웃 상향 / 테스트 격리
3. 1회 재시도 후에도 실패하면 근본 원인 수정 우선

## 스택별 명령어

### JS/TS
- install: `pnpm install` | `yarn` | `npm install`
- typecheck: `pnpm typecheck` 또는 `tsc -p .`
- lint: `pnpm lint` 또는 `eslint .`
- test: `pnpm test` (vitest: `pnpm vitest run` / jest: `pnpm jest --runInBand`)

### Python
- install: `pip install -r requirements.txt`
- typecheck: `pyright` 또는 `mypy`
- lint/format: `ruff check .` / `ruff format .`
- test: `pytest -q`

## 패키지 매니저 자동 감지
- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn
- `package-lock.json` → npm
- 둘 이상 존재 시: pnpm > yarn > npm 우선

---
name: archive
description: Archives completed items from PROGRESS.md to ARCHIVE_YYYY_MM.md monthly log. Use when PROGRESS.md exceeds 5KB, has 20+ done items, or when the user says "아카이브", "archive", or "정리".
disable-model-invocation: true
---

# 아카이브 워크플로우

PROGRESS.md의 완료된 항목을 월별 아카이브 파일로 이동합니다.

## 실행 순서

1. **PROGRESS.md 읽기** — 완료 항목(Done) 확인
2. **아카이브 파일 확인** — `ARCHIVE_YYYY_MM.md` 존재 여부 확인
3. **완료 항목 이동**:
   - Done 섹션의 `[x]` 항목들을 `ARCHIVE_YYYY_MM.md`로 이동
   - 현재 년월 기준으로 파일명 결정 (예: `ARCHIVE_2026_02.md`)
4. **PROGRESS.md 정리** — Done 섹션 비우기, Open/Next 유지

## 아카이브 파일 형식

```markdown
# Archive — YYYY년 MM월

## 완료 항목
- [x] 항목 내용 (YYYY-MM-DD)
- [x] 항목 내용 (YYYY-MM-DD)
```

## 규칙
- 기존 아카이브 파일이 있으면 **하단에 추가** (덮어쓰기 금지)
- Open/Issues/Next 항목은 **절대 이동하지 않음**
- 아카이브 후 PROGRESS.md 파일 크기가 줄었는지 확인
- 완료 후 "✅ N개 항목을 ARCHIVE_YYYY_MM.md로 이동했습니다" 출력

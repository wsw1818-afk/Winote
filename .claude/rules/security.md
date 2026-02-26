# 보안 규칙

## 비밀정보 절대 규칙
- NEVER: 실제 토큰/비밀번호/키스토어 패스워드를 코드/문서/설정/예시에 포함
- ALWAYS: `.env` / OS Keychain / CI Secret / Password Manager 사용
- 문서에는 플레이스홀더만: `YOUR_TOKEN_HERE`, `YOUR_PASSWORD_HERE`

## 코드 보안
- OWASP Top 10 취약점 방지 (XSS, SQL injection, 명령어 주입 등)
- 외부 패키지: 유지관리/라이선스 확인 후 최소 추가
- 사용자 데이터/로그: 개인정보 마스킹

## 자동 실행 예외 (반드시 확인 필요)
1. 데이터 손실 위험이 있는 파괴적 작업 (`git reset --hard`, `rm -rf`, DB drop)
2. 비밀정보가 포함/노출될 가능성
3. 비용이 큰 작업이고 사용자 요구가 불명확할 때
4. 사용자가 "확인해줘/물어봐"를 명시한 경우

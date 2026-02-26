---
name: deploy
description: Builds and deploys project artifacts to the designated OneDrive output folder. Supports Expo/RN APK/AAB, .NET WPF exe, and Flutter builds. Use when the user says "배포", "deploy", "빌드해줘", or "APK 만들어줘".
argument-hint: [debug|release]
disable-model-invocation: true
---

# 배포 워크플로우

프로젝트를 빌드하고 결과물을 지정된 배포 경로로 복사합니다.

## 1단계: 프로젝트 타입 감지

파일 기반으로 프로젝트 타입을 자동 감지:

| 파일 | 프로젝트 타입 |
|------|-------------|
| `app.json` + `expo` | Expo/React Native |
| `*.csproj` + `<OutputType>WinExe` | .NET WPF |
| `pubspec.yaml` | Flutter |

## 2단계: 빌드 타입 결정

사용자가 지정하지 않으면 **기본값은 Debug** 빌드입니다.

- "릴리즈", "release", "배포용" → Release 빌드
- 그 외 → Debug 빌드

## 3단계: 빌드 전 체크

- [ ] 이번 세션에서 수정한 파일 목록 확인
- [ ] Native 코드(*.kt, *.java, *.swift) 수정 여부 확인
- [ ] JS/TS만 수정 → "빌드 불필요, Hot Reload 사용" 안내 후 종료

## 4단계: 빌드 실행

### Expo/React Native
```bash
# Debug
cd android && ./gradlew.bat assembleDebug && cd ..

# Release (캐시 정리 필수)
powershell -Command "Remove-Item -Recurse -Force '.expo','node_modules/.cache','android/app/build','android/.gradle' -ErrorAction SilentlyContinue"
cd android && ./gradlew.bat clean assembleRelease && cd ..
```

### .NET WPF
```bash
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
```

### Flutter
```bash
# build_windows.bat에서 Flutter 경로 확인 후 실행
```

## 5단계: 배포 경로로 복사

CLAUDE.md 글로벌 설정의 §29 배포 경로 매핑 테이블을 참조하여 복사합니다.

## 6단계: 검증

- Release APK는 JavaScript 번들 내용 검증 (§28.4)
- 빌드 성공 메시지와 파일 경로 출력
- PROGRESS.md 업데이트, .commit_message.txt 갱신

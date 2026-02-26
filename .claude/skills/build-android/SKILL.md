---
name: build-android
description: Builds Android APK/AAB for Expo/React Native projects with cache cleanup, JS bundle verification, and automatic output copy. Use when the user says "안드로이드 빌드", "APK", "AAB", or needs Android build.
argument-hint: [debug|release|aab]
disable-model-invocation: true
---

# Android 빌드 워크플로우

Expo/React Native 프로젝트의 Android APK/AAB를 빌드합니다.

## 빌드 전 필수 체크

다음 조건을 모두 확인합니다:

1. **Native 코드 수정 여부**: `*.kt`, `*.java`, `*.swift`, `*.m` 파일 수정 확인
2. **설정 파일 수정 여부**: `app.json`, `AndroidManifest.xml`, `build.gradle` 확인
3. **사용자 명시적 요청**: "빌드해줘", "APK", "AAB" 등

JS/TS만 수정한 경우:
```
✅ 빌드 불필요 - JavaScript 코드만 수정했습니다.
앱에서 Reload(r 키)만 하면 변경사항이 즉시 적용됩니다.
```

## Debug 빌드 (기본)

```bash
cd android && .\gradlew.bat assembleDebug && cd ..
```

## Release 빌드 (명시적 요청 시)

```bash
# 1. 캐시 4종 정리 (필수!)
powershell -Command "Remove-Item -Recurse -Force '.expo','node_modules\.cache','android\app\build','android\.gradle' -ErrorAction SilentlyContinue"

# 2. Clean Release 빌드
cd android && .\gradlew.bat clean assembleRelease && cd ..
```

## Release AAB (플레이스토어용)

```bash
powershell -Command "Remove-Item -Recurse -Force '.expo','node_modules\.cache','android\app\build','android\.gradle' -ErrorAction SilentlyContinue"
cd android && .\gradlew.bat clean bundleRelease && cd ..
```

## 빌드 후 검증 (Release 필수)

```bash
# JS 번들 최신 코드 포함 확인
unzip -p "android/app/build/outputs/apk/release/app-release.apk" assets/index.android.bundle | grep -c "검증할_키워드"
# 결과가 0이면 오래된 번들 → 캐시 재정리 후 재빌드
```

## 결과물 복사

CLAUDE.md §29 배포 경로 매핑 테이블 참조하여 자동 복사합니다.

## AdMob 모드 확인

- Debug: 테스트 광고 ID 또는 null
- Release: 프로덕션 광고 ID (§30 참조)

#!/bin/bash
# Flutter iOS 빌드 사전 검증 스크립트

set -e

echo "========== iOS 빌드 사전 검증 시작 =========="

# 1. 필수 파일 확인
echo "1. 필수 파일 존재 확인..."
[ -f "pubspec.yaml" ] || { echo "❌ pubspec.yaml 없음"; exit 1; }
[ -d "lib" ] || { echo "❌ lib/ 디렉토리 없음"; exit 1; }
[ -d "ios" ] || { echo "❌ ios/ 디렉토리 없음"; exit 1; }
[ -f "ios/Runner.xcodeproj/project.pbxproj" ] || { echo "❌ Xcode 프로젝트 없음"; exit 1; }
echo "✅ 필수 파일 존재"

# 2. Info.plist 버전 확인
echo "2. Info.plist 버전 형식 확인..."
VERSION=$(grep -A1 "CFBundleShortVersionString" ios/Runner/Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
if [[ "$VERSION" =~ ^\$\( ]]; then
  echo "❌ Info.plist 버전이 변수: $VERSION"
  echo "   1.0.0 같은 숫자 형식이어야 함"
  exit 1
fi
echo "✅ Info.plist 버전: $VERSION"

# 3. Git 추적 확인
echo "3. ios/ 파일 Git 추적 확인..."
IOS_FILES=$(git ls-files ios/ | wc -l)
if [ "$IOS_FILES" -lt 10 ]; then
  echo "❌ ios/ 파일이 Git에 $IOS_FILES개만 추적됨"
  echo "   최소 10개 이상 필요 (Generated.xcconfig, Info.plist 등)"
  exit 1
fi
echo "✅ ios/ 파일 ${IOS_FILES}개 추적됨"

# 4. Flutter pub get 테스트
echo "4. Flutter pub get 테스트..."
FLUTTER_CMD="${FLUTTER_CMD:-C:/flutter/bin/flutter.bat}"
"$FLUTTER_CMD" pub get > /dev/null 2>&1 || { echo "❌ flutter pub get 실패"; exit 1; }
echo "✅ flutter pub get 성공"

# 5. iOS Flutter 파일 생성 확인
echo "5. iOS Flutter 생성 파일 확인..."
[ -f "ios/Flutter/Generated.xcconfig" ] || { echo "❌ Generated.xcconfig 없음"; exit 1; }
[ -f "ios/Flutter/flutter_export_environment.sh" ] || { echo "❌ flutter_export_environment.sh 없음"; exit 1; }
echo "✅ Flutter 생성 파일 존재"

# 6. Podfile 존재 확인 (선택)
echo "6. Podfile 확인..."
if [ ! -f "ios/Podfile" ]; then
  echo "⚠️  Podfile 없음 (EAS 빌드에서 자동 생성됨)"
else
  echo "✅ Podfile 존재"
fi

# 7. 업로드 크기 예상
echo "7. 업로드 크기 예상..."
SIZE=$(du -sh . 2>/dev/null | awk '{print $1}')
echo "   전체 프로젝트 크기: $SIZE"
echo "   (gitignore 제외 후 예상: ~50-70MB)"

echo ""
echo "=========================================="
echo "✅ 모든 사전 검증 통과!"
echo "=========================================="
echo ""
echo "다음 단계: npx eas build --platform ios --profile ios-simulator"

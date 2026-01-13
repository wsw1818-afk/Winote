# Winote

> S펜/스타일러스 최적화 태블릿 필기 앱 (Windows + Android)

## 개요

**Winote**는 갤럭시북(Windows)과 갤럭시탭(Android)에서 동시에 사용할 수 있는 필기 중심 노트 앱입니다.

### 핵심 가치

- **펜이 주인공**: 저지연 입력, 손바닥 거부, 펜 버튼/제스처 지원
- **PDF 워크플로**: 자료 열고 → 바로 쓰고 → 요약/태그 → 공유
- **정리 자동화**: 제목/태그 추천, 필기 검색 (OCR)
- **완벽한 동기화**: Windows ↔ Android 실시간 동기화

## 기술 스택

- **프레임워크**: Flutter 3.x
- **상태 관리**: Riverpod
- **데이터베이스**: SQLite (drift)
- **PDF**: Syncfusion PDF Viewer
- **플랫폼**: Android 8.0+, Windows 10+

## 프로젝트 구조

```
lib/
├── core/           # 공통 유틸리티, 상수
├── data/           # 데이터 소스, 레포지토리 구현
├── domain/         # 엔티티, 서비스, 레포지토리 인터페이스
├── presentation/   # UI, 위젯, 페이지, 상태 관리
├── platform/       # 네이티브 플랫폼 채널
└── main.dart
```

## 문서

- [기획서 (PRD)](docs/PRD.md) - 제품 요구사항 및 기능 정의
- [아키텍처](docs/ARCHITECTURE.md) - 기술 아키텍처 및 설계
- [개발 티켓](docs/TICKETS.md) - 작업 목록 및 진행 상황

## 시작하기

### 요구사항

- Flutter SDK 3.16.0 이상
- Dart 3.2.0 이상
- Android Studio (Android 빌드용)
- Visual Studio 2022 (Windows 빌드용)

### 설치

```bash
# 의존성 설치
flutter pub get

# 코드 생성 (drift, json_serializable)
flutter pub run build_runner build

# Android 실행
flutter run -d android

# Windows 실행
flutter run -d windows
```

### 빌드

```bash
# Android APK
flutter build apk --release

# Windows exe
flutter build windows --release
```

## 로드맵

### Phase 1: MVP (6주)
- [x] 프로젝트 설정
- [ ] 필기 엔진
- [ ] 노트 관리
- [ ] PDF 주석
- [ ] 로컬 저장

### Phase 2: 차별화 (4주)
- [ ] 계정/동기화
- [ ] OCR 검색
- [ ] AI 요약

### Phase 3: 확장 (4주)
- [ ] 녹음 동기화
- [ ] 협업 기능
- [ ] 템플릿 마켓

## 라이선스

MIT License

## 기여

이슈 및 PR 환영합니다!

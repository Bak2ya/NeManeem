<div align="center">
  <img src="Resources/NeManeemIconMaster.png" width="128" alt="NeManeem app icon">

# NeManeem

  <a href="https://apps.apple.com/app/id6806773845">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/ko-kr?size=250x83" alt="Mac App Store에서 다운로드" height="55">
  </a>
</div>

---

## 한국어

> 메뉴바에서 네트워크를 더 쉽게 보고, 필요한 만큼만 관리하는 Mac 앱입니다.

NeManeem은 메뉴바에서 간단히 네트워크 속도를 확인하는 것부터 앱별 네트워크 사용량 조회, 사용량 기록과 통계, 데이터 한도 관리, 앱별 네트워크 차단까지 할 수 있는 앱입니다.

평소에는 필요한 정보만 간단하게 보고, 더 자세히 확인하고 싶을 때는 팝오버나 독립된 모니터 창을 열어 앱별 네트워크 사용량을 확인할 수 있습니다.

### 주요 기능

- 메뉴바에서 실시간 업로드 / 다운로드 속도 확인
- 앱별 네트워크 사용량 확인
- 팝오버와 독립된 모니터 창
- 전체 사용량 기록 및 통계
- 특정 작업이나 시간의 사용량을 따로 측정하는 세션 기록
- 기록 및 요약 내보내기
- 데이터 한도 설정 및 단계별 경고
- 모든 네트워크 또는 특정 네트워크별 데이터 한도 관리
- 사용자가 선택한 앱의 네트워크 연결 차단
- 인터넷 트래픽과 로컬 네트워크 트래픽 구분
- 앱 / 프로세스 정보 확인 및 Finder에서 위치 보기
- 관련 프로세스를 상위 앱으로 묶어 표시하는 옵션
- 표시 크기, 단위, 갱신 주기, 화면 모드 등 다양한 사용자 설정

### v1.1

NeManeem 1.1에서는 macOS 27의 레이아웃 변화에 맞춰 설정 화면을 조정하고, 선택 상태와 시스템 강조 색상 표현을 다듬었습니다.

앱이 많은 환경에서의 반응성과 사용량 기록 효율을 개선했고, 사용량 화면과 기록·요약 내보내기, 세션 데이터 관리도 정리했습니다. 앱/프로세스 정보와 Finder에서 위치 보기, 관련 프로세스 묶기 기능을 보강했으며, 팝오버 미리보기와 키보드 조작, 손쉬운 사용, 앱 제한 기능의 안정성도 개선했습니다.

자세한 변경 내용은 [CHANGELOG.md](CHANGELOG.md)를 확인해 주세요.

### 어렵지 않게

NeManeem은 네트워크 관리 도구에 익숙하지 않은 사람도 사용할 수 있도록 만들었습니다.

기본 화면에서는 프로세스나 복잡한 네트워크 용어보다 앱을 중심으로 이해하기 쉬운 정보를 보여주고, 더 자세한 정보와 기능은 필요할 때 선택해서 사용할 수 있도록 구성했습니다.

기능을 켜기 위해 Mac의 권한이 필요한 경우에는 왜 필요한지 먼저 설명한 뒤 사용자가 직접 선택하도록 합니다. 앱별 네트워크 차단 기능도 기본적으로 꺼져 있으며 사용자가 직접 활성화해야 동작합니다.

### 개인정보 보호

NeManeem은 핵심 기능을 위해 외부 백엔드, 분석(Analytics), 광고, 로그인, 결제 또는 AI 서비스를 사용하지 않습니다.

사용량 기록과 통계는 관련 기능을 켠 경우 사용자의 Mac에 로컬로 저장되며, NeManeem이 자동으로 외부 서버에 전송하지 않습니다.

또한 다음과 같은 정보를 저장하지 않도록 설계했습니다.

- 방문한 URL 또는 도메인
- 패킷 내용 또는 통신 내용
- 원격 엔드포인트
- 브라우징 기록
- 위치 좌표

현재 Wi-Fi 이름(SSID)을 식별하는 기능은 선택 사항입니다. 시스템이 위치 권한을 요구할 수 있지만, NeManeem은 이를 네트워크 이름을 식별하는 용도로만 사용하며 지리적 위치 좌표를 읽거나 저장하지 않습니다.

자세한 내용은 [개인정보 처리방침](PRIVACY.md)을 확인해 주세요.

### 지원 언어

- 한국어
- English
- 日本語
- Español

### 시스템 요구사항

- macOS 13.0 이상

일부 기능은 Network Extension / System Extension을 사용하며, 해당 기능을 사용하려면 사용자의 승인이 필요합니다.

### 소스 빌드

소스에서 직접 빌드하려면 [BUILDING.md](BUILDING.md)를 확인해 주세요.

### 이름 이야기

제 고양이 이름이 **마님**이에요. 그래서 **‘내 마님’**, NeManeem입니다. 😁

### 제작

**이 앱은 마님이와 Bak2YA가 ChatGPT와 함께 만들었습니다.**

---

## English

> A Mac menu bar app for seeing your network activity more clearly and managing only what you need.

NeManeem lets you check live network speed from the menu bar, inspect per-app network usage, keep usage history and statistics, manage data limits, and optionally block network access for selected apps.

For quick checks, the menu bar keeps things simple. When you need more detail, you can open the popover or a separate monitor window to inspect per-app network activity.

### Features

- Live upload / download speed in the menu bar
- Per-app network usage
- Popover and standalone monitor window
- Usage history and statistics
- Session recording for measuring specific tasks or time periods
- Record and summary export
- Data limits with staged warnings
- Global or network-specific data-limit management
- Optional network blocking for selected apps
- Separate internet and local-network traffic views
- App / process information with Reveal in Finder
- Optional grouping of related processes under their parent app
- Configurable display size, units, refresh interval, appearance, and more

### v1.1

NeManeem 1.1 updates the Settings layout for macOS 27 and refines selection states and system accent color behavior.

It also improves responsiveness and usage-recording efficiency on Macs with many applications, reorganizes the Usage section, and improves record export, summary export, and session data management. App/process information, Reveal in Finder, related-process grouping, popover previews, keyboard navigation, accessibility behavior, and app-limiting reliability have also been improved.

See [CHANGELOG.md](CHANGELOG.md) for the full release notes.

### Designed to stay approachable

NeManeem is designed to be usable even if you are not familiar with network-management tools.

The default interface focuses on apps and understandable information rather than exposing process-level or networking terminology everywhere. More detailed controls remain available when you need them.

When a feature requires a system permission, NeManeem explains why before you choose whether to enable it. App-specific network blocking is off by default and only works after you explicitly enable it.

### Privacy

NeManeem does not use an external backend, analytics, advertising, login, payments, or AI services for its core functionality.

When enabled, usage history and statistics are stored locally on your Mac and are not automatically sent to an external server.

NeManeem is designed not to store:

- Visited URLs or domains
- Packet or communication contents
- Remote endpoints
- Browsing history
- Geographic coordinates

Identifying the current Wi-Fi name (SSID) is optional. The system may require Location permission for this capability, but NeManeem uses it only to identify the network name and does not read or store geographic coordinates.

See [PRIVACY.md](PRIVACY.md) for details.

### Languages

- 한국어
- English
- 日本語
- Español

### System requirements

- macOS 13.0 or later

Some features use Network Extension / System Extension and require user approval before they can operate.

### Building from source

See [BUILDING.md](BUILDING.md).

### About the name

My cat's name is **Maneem**. So, **“my Maneem”** — NeManeem. 😁

### Created by

**Made by Maneem and Bak2YA with ChatGPT.**

---

## License

NeManeem is released under the [MIT License](LICENSE).

Apple, the Apple logo, and Mac are trademarks of Apple Inc., registered in the U.S. and other countries and regions. Mac App Store is a service mark of Apple Inc.

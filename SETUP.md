# 셋업

[Blink Shell](https://github.com/blinksh/blink)을 **개인 Apple Developer 계정으로
직접 서명해서 자기 아이폰/아이패드에 설치**하기 위한 예시 저장소다.
App Store 버전을 사지 않고 소스에서 빌드해 쓰는 경로를 정리했다.

단축키 사용법은 [`SHORTCUT.md`](SHORTCUT.md)에 따로 있다.

## 목차

- [원본과 다른 점](#원본과-다른-점)
- [준비물](#준비물)
- [1. 클론](#1-클론)
- [2. 의존성 내려받기](#2-의존성-내려받기)
- [3. 서명 설정](#3-서명-설정)
- [4. Xcode에서 빌드](#4-xcode에서-빌드)
- [5. 기기에서 개발자 신뢰](#5-기기에서-개발자-신뢰)
- [서명이 실패할 때](#서명이-실패할-때)
- [서명 만료](#서명-만료)
- [ipa로 보관해 두기](#ipa로-보관해-두기)
- [원본 업데이트 받기](#원본-업데이트-받기)
- [Debug와 Release](#debug와-release)
- [원격 접속 구성 예시](#원격-접속-구성-예시)
- [라이선스](#라이선스)

## 원본과 다른 점

`blinksh/blink`의 `raw` 브랜치(`a90b4423`)를 그대로 가져오고 아래만 고쳤다.
앱 기능은 건드리지 않았고, 소스 코드 변경은 한 줄도 없다.

**서명이 통과하게 만들기 위한 변경**

| 바꾼 것 | 왜 |
|---|---|
| `DEVELOPMENT_TEAM`을 `"$(TEAM_ID)"`로 (`project.pbxproj` 8곳) | 원본에는 Blink 팀 ID가 박혀 있다. 그대로 두면 남의 팀으로 서명하려다 실패한다. `developer_setup.xcconfig`의 값을 읽도록 바꿨다 |
| `com.apple.developer.web-browser` entitlement 제거 | Apple 승인을 따로 받아야 쓸 수 있는 권한이라 개인 계정 프로파일에 들어가지 않는다. 남겨 두면 서명 단계에서 막힌다 |

**그 밖에 지운 것**

| 지운 것 | 왜 |
|---|---|
| `Blink.xcodeproj/.../xcshareddata/` 3개 | 원본 저장소의 워크스페이스 설정이다. 원본 README도 클론 직후 지우라고 안내한다 |
| `.github/workflows/build.yml` | 존재하지 않는 Xcode 15.0 경로를 지정해 push마다 반드시 실패한다. 개인 빌드에는 쓸 일이 없다 |

전체 차이를 직접 확인하려면 [원본 업데이트 받기](#원본-업데이트-받기)의 upstream을
추가한 뒤 실행한다.

```sh
git diff --name-status a90b4423 HEAD
```

## 준비물

| 항목 | 조건 |
|---|---|
| macOS | Xcode 15 이상이 도는 버전 |
| Xcode | 15 이상 |
| 실기기 | iOS 17.6 이상 (프로젝트 배포 타겟) |
| Apple 계정 | 아래 표 참고 |
| 디스크 | 8GB 이상 여유 (의존성 받은 저장소 1.2GB + DerivedData 3GB) |

Apple 계정은 무료와 유료의 차이가 결과물의 수명으로 나타난다.

| 계정 | 비용 | 서명 유효기간 |
|---|---|---|
| 무료 Apple ID | 없음 | **7일**. 매주 다시 빌드해서 설치해야 한다 |
| Apple Developer Program | 연 $99 | **1년** |

7일마다 재설치하는 것이 생각보다 번거롭다. 계속 쓸 생각이면 유료 계정이 편하다.

## 1. 클론

```sh
git clone --recursive https://github.com/devstefancho/blink-example.git
cd blink-example
```

`--recursive`를 빠뜨렸다면:

```sh
git submodule update --init --recursive
```

서브모듈은 `ios_system`과 `MBProgressHUD` 두 개다. 없으면 빌드가 안 된다.

## 2. 의존성 내려받기

먼저 Xcode 명령줄 도구가 아니라 Xcode 본체를 가리키는지 확인한다.

```sh
xcode-select -p
# /Applications/Xcode.app/Contents/Developer 가 나와야 한다
```

`/Library/Developer/CommandLineTools`가 나오면 바꾼다.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

그 다음 두 스크립트를 순서대로 돌린다.

```sh
./get_frameworks.sh
./get_resources.sh
```

| 스크립트 | 하는 일 |
|---|---|
| `get_frameworks.sh` | `xcfs/`의 Swift Package를 resolve해서 미리 빌드된 xcframework를 받는다. mosh, LibSSH, OpenSSL, Protobuf, ios_system 등 |
| `get_resources.sh` | vim runtime(9.1.0187)을 받아 `Resources/vim/`에 푼다 |

`get_frameworks.sh`는 네트워크 상태에 따라 몇 분 걸린다. 이쪽이 받는 파일은
SHA256 체크섬이 `xcfs/Package.swift`에 전부 박혀 있어서 Swift Package Manager가
대조한다. 값이 다르면 resolve가 실패한다.

**`get_resources.sh`에는 그 대조가 없다.** upstream 원본 그대로이며, HTTPS로
받기는 하지만 내려받은 zip의 무결성을 확인하지 않고 바로 푼다. 실제 위험은
낮다(blinksh 조직 계정이 탈취되는 상황이 전제고, 그 정도면 소스를 직접 고치는
편이 빠르다). 다만 두 스크립트의 검증 수준이 다르다는 점은 알고 실행한다.

## 3. 서명 설정

템플릿을 복사한다.

```sh
cp template_setup.xcconfig developer_setup.xcconfig
```

`developer_setup.xcconfig`를 열어 다음 값을 자기 것으로 바꾼다.

| 키 | 넣을 값 | 예 |
|---|---|---|
| `TEAM_ID` | 본인 Team ID (영숫자 10자) | `A1B2C3D4E5` |
| `BUNDLE_ID` | 본인이 정한 역방향 도메인 | `com.example.blink` |
| `GROUP_ID` | 앱 그룹 접두사 | `com.example` |
| `CLOUD_ID` | iCloud 컨테이너 이름. `BUNDLE_ID`와 같게 두면 된다 | `com.example.blink` |
| `KEYCHAIN_ID1` | 키체인 그룹. `GROUP_ID`와 같게 두면 된다 | `com.example` |

Team ID는 [Apple Developer](https://developer.apple.com/account)의 Membership
페이지에 있다. 무료 계정이라면 Xcode의 Settings > Accounts에서 팀을 고르면
자동으로 잡히기도 한다.

`BUNDLE_ID`는 **다른 사람이 쓰는 값과 겹치면 안 된다.** 원본의
`sh.blink.blinkshell`을 그대로 두면 App Store의 진짜 Blink와 충돌한다.
본인이 소유한 도메인을 뒤집어 쓰는 것이 원칙이지만, 개인 설치용이면
`com.본인아이디.blink` 정도로도 문제없다.

> `developer_setup.xcconfig`는 `.gitignore`에 걸려 있어 커밋되지 않는다.
> 의도한 것이다. 대신 **이 파일은 이 맥에만 있다.** 머신을 옮기면
> `template_setup.xcconfig`를 다시 복사해서 값을 채워야 한다.

## 4. Xcode에서 빌드

```sh
open Blink.xcodeproj
```

1. 스킴을 **Blink**로 둔다
2. 아이폰/아이패드를 연결하고 Product > Destination에서 고른다
3. `Cmd` `R`

첫 빌드는 15~30분 걸린다. 두 번째부터는 훨씬 빠르다.

## 5. 기기에서 개발자 신뢰

빌드는 됐는데 앱을 누르면 "신뢰할 수 없는 개발자"가 뜨는 경우다.
기기에서 다음 경로로 들어가 본인 계정을 신뢰한다.

```
Settings > General > VPN & Device Management > Developer App > (본인 계정) > Trust
```

## 서명이 실패할 때

Blink는 iCloud, 푸시 알림, 키체인 공유, 연관 도메인 같은 권한을 여럿 쓴다.
계정 종류에 따라 일부가 막힌다. 막힌 것부터 끄면 된다.

Xcode에서 Blink 타겟 > Signing & Capabilities로 가서 아래 항목을 지운다.

| Capability | 없어도 되는가 |
|---|---|
| Push Notifications | 된다. 알림만 안 온다 |
| iCloud | 된다. 설정 동기화만 안 된다 |
| Keychain Sharing | 된다 |
| Associated Domains | 된다. `webcredentials:blink.sh`는 원래 blink.sh 소유자용이다 |

`Blink/Blink.entitlements`에서 해당 키를 직접 지워도 결과는 같다.
서브 타겟(`BlinkFileProviderExtension` 등)에도 각자 entitlements 파일이 있으니,
그쪽에서 막히면 같이 손본다.

## 서명 만료

개인 서명 빌드는 **만료일이 지나면 앱이 실행되지 않는다.** 아이콘은 그대로 남아
있고 누르면 바로 닫힌다. 앱 데이터가 지워지는 것은 아니고 서명만 무효가 된다.
다시 빌드해서 설치하면 하던 설정이 그대로 살아 있다.

현재 설치본의 만료일을 확인하려면:

```sh
APP=~/Library/Developer/Xcode/DerivedData/Blink-*/Build/Products/Debug-iphoneos/Blink.app
WORK=$(mktemp -d)
security cms -D -i "$APP/embedded.mobileprovision" > "$WORK/prov.plist"
/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$WORK/prov.plist"
rm -rf "$WORK"
```

유료 계정이면 1년이니 만료 한 달쯤 전에 다시 빌드해 두면 된다.

`/tmp/prov.plist` 같은 고정 경로 대신 `mktemp -d`를 쓰는 이유가 있다. `/tmp`는
누구나 쓰는 디렉토리라 다른 사용자나 프로세스가 같은 이름의 심볼릭 링크를 미리
깔아 둘 수 있고, 그러면 `>` 리다이렉트가 링크를 따라가 엉뚱한 파일을 덮어쓴다.
게다가 복호화된 프로파일에는 아래에 적은 신원 정보가 평문으로 들어 있어서
남이 읽을 수 있는 곳에 두면 안 된다. 다 쓰고 지우는 것까지가 한 세트다.

## ipa로 보관해 두기

빌드 결과는 `~/Library/Developer/Xcode/DerivedData/`에 있고, **Xcode가 정리하거나
용량을 확보하다가 지운다.** 다시 빌드하면 되지만 의존성부터 다시 받아야 해서
오래 걸린다. 한 번 성공한 빌드는 ipa로 묶어 두는 편이 낫다.

```sh
WORK=$(mktemp -d)
mkdir -p "$WORK/Payload"
cp -R ~/Library/Developer/Xcode/DerivedData/Blink-*/Build/Products/Debug-iphoneos/Blink.app \
  "$WORK/Payload/"
(cd "$WORK" && zip -qry Blink.ipa Payload)
mv "$WORK/Blink.ipa" ~/Blink.ipa
rm -rf "$WORK"
```

여기서도 `/tmp` 고정 경로를 쓰지 않는다. 만들어지는 ipa 안에 아래 표의 신원
정보가 그대로 들어가기 때문이다.

> **ipa를 공개된 곳에 올리지 않는다.** ipa 안의 `embedded.mobileprovision`에는
> 서명한 사람의 정보가 평문으로 들어 있다. 압축을 풀고 명령 한 줄이면 누구나 읽는다.
>
> ```sh
> unzip Blink.ipa 'Payload/Blink.app/embedded.mobileprovision'
> security cms -D -i Payload/Blink.app/embedded.mobileprovision
> ```
>
> | 나오는 것 | 왜 곤란한가 |
> |---|---|
> | Apple 계정에 등록된 **실명** | GitHub 핸들과 실명이 공개적으로 연결된다 |
> | 본인 **Team ID** | 저장소에는 없는 값이다 |
> | 개발자 인증서 정보 | 이름, 시리얼, 유효기간 |
> | 등록된 기기 **UDID 전체** | 하드웨어 고유값이라 **바꿀 수 없다** |
>
> 빌드한 앱 바이너리에도 맥의 홈 디렉토리 경로(`/Users/사용자명/...`)가 남는다.
> 개인키는 들어가지 않으니 서명 사칭은 안 되지만, 신원과 기기 목록은 그대로 샌다.
> ipa는 로컬이나 비공개 저장소에만 두고, GitHub Release처럼 저장소를 public으로
> 바꾸면 같이 공개되는 곳에는 올리지 않는다.

> **GPL 주의.** 이 ipa를 남에게 건네주면 GPL-3.0의 "배포"에 해당하고, 그 시점에
> 수정한 소스를 함께 제공할 의무가 생긴다. 이 저장소처럼 소스를 공개해 두고
> 링크를 같이 주면 그 의무는 충족된다.

## 원본 업데이트 받기

```sh
git remote add upstream https://github.com/blinksh/blink.git
git fetch upstream
git merge upstream/raw
```

`project.pbxproj`와 `Blink.entitlements`는 원본에서도 자주 바뀌는 파일이라
**충돌이 날 가능성이 높다.** 충돌이 나면 다음 두 가지는 반드시 이쪽 값으로
되돌린다. 그러지 않으면 서명 단계에서 다시 실패한다.

| 되돌릴 것 | 이쪽 값 |
|---|---|
| `DEVELOPMENT_TEAM` | `"$(TEAM_ID)"` |
| `com.apple.developer.web-browser` | 제거된 상태 유지 |

머지가 끝나면 의존성을 다시 받는다. 원본이 xcframework 버전을 올렸을 수 있다.

```sh
./get_frameworks.sh
./get_resources.sh
```

## Debug와 Release

`Cmd` `R`로 그냥 빌드하면 Debug 구성이다. 개인용으로 쓰는 데는 문제가 없지만
Release보다 느리고 앱 용량이 크다(180MB 안팎).

성능이 아쉬우면 Product > Scheme > Edit Scheme > Run > Build Configuration을
Release로 바꾼다.

## 원격 접속 구성 예시

Blink를 폰에 깔았다면 그 다음 문제는 "집 밖에서 내 맥에 어떻게 붙는가"다.
아래는 그중 한 가지 조합이다. Blink 자체와는 무관하니 다른 방식을 써도 된다.

```
폰(Blink) → Tailscale → mosh → 터미널 멀티플렉서 → 맥의 셸
```

각자 하는 일이 겹치지 않는다.

| 도구 | 역할 | 없으면 |
|---|---|---|
| Blink | 폰에서 터미널 화면 | 폰에서 터미널을 못 씀 |
| Tailscale | 폰과 맥을 같은 사설망으로 묶음 | 공유기 포트 열기, 바뀌는 집 IP 추적, 방화벽 뚫기를 직접 해야 함 |
| mosh | 연결 유지 (IP가 바뀌어도 안 끊김) | 와이파이/LTE 전환마다, 화면 끌 때마다 SSH 재접속 |
| tmux 등 멀티플렉서 | 맥에서 작업 세션을 붙잡고 있음 | 연결이 끊기면 돌던 프로세스도 같이 죽음 |

### mosh를 쓰는 이유

1. **안 끊긴다.** 처음에 SSH로 로그인만 하고, 그 뒤로는 UDP로 따로 통신한다.
   서버가 세션 상태를 들고 있어서 폰 IP가 바뀌든 몇 시간 뒤에 돌아오든 이어진다.
2. **타이핑이 즉시 보인다.** SSH는 글자마다 서버 왕복을 기다린다. mosh는 결과를
   예측해서 화면에 미리 그리므로 느린 회선에서도 렉이 덜 느껴진다.

한계는 mosh 자체에 스크롤백이 없다는 것이다. tmux 같은 멀티플렉서가 그 역할을 한다.

### 접속할 때 실제로 일어나는 일

1. Blink에서 `mosh 맥이름`을 친다
2. Tailscale이 그 이름을 사설망 주소로 풀어 준다
3. SSH로 딱 한 번 로그인한다
4. 맥에서 `mosh-server`가 뜨고 자기 포트 번호와 세션 키를 알려준다
5. SSH 연결은 여기서 끊긴다 (할 일이 끝났다)
6. 이제부터 폰과 맥이 UDP로 직접 대화한다
7. 멀티플렉서 세션에 붙으면 하던 작업이 그대로 나온다

3번의 SSH는 mosh를 띄우기 위한 심부름이고, 진짜 연결은 6번부터다.
지하철에서 끊겨도 1~5번을 다시 하지 않고 6번이 알아서 다시 이어붙는다.

### 맥 쪽 준비

mosh는 클라이언트가 폰(Blink 내장)에 있고 서버가 맥에 있는 구조라
`mosh-server`를 따로 깔아야 한다.

```sh
brew install mosh
brew install --cask tailscale
```

**폰과 맥의 mosh 메이저 버전이 맞아야 한다.** Blink에 내장된 mosh 버전은
`xcfs/Package.swift`에서 확인한다. 이 저장소 기준으로는 1.4.0이다.
`brew upgrade`로 맥 쪽만 크게 올라가면 접속이 안 될 수 있다.
mosh 연결만 갑자기 실패하면 `mosh-server --version`부터 확인한다.

점검용:

```sh
tailscale status              # 기기 목록과 온라인 여부
which mosh-server tailscale   # 맥 쪽 설치 확인
```

## 라이선스

Blink Shell은 GPL-3.0이다. 이 저장소도 같은 라이선스를 따른다.
전문은 [`COPYING`](COPYING)에 있다.

원본 프로젝트: https://github.com/blinksh/blink

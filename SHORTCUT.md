# 단축키

Blink에서 쓸 수 있는 키보드 단축키와 제스처 정리. 표에 적힌 기본값은 모두
소스에서 확인한 값이다 (`KB/Native/Model/KeyShortcut.swift`의 `defaultList`).

외장 키보드가 붙어 있어야 대부분의 단축키가 동작한다. 화면 키보드만 쓸 때는
아래 [제스처](#제스처)와 [Smart Keys 바](#smart-keys-바)를 쓴다.

## 목차

- [기본 단축키](#기본-단축키)
- [Snippets 창 안에서](#snippets-창-안에서)
- [제스처](#제스처)
- [Smart Keys 바](#smart-keys-바)
- [단축키 바꾸기](#단축키-바꾸기)
- [기본값이 없는 액션](#기본값이-없는-액션)
- [터미널 키 리매핑](#터미널-키-리매핑)

## 기본 단축키

### 탭

| 키 | 하는 일 |
|---|---|
| `Cmd` `T` | 새 탭 |
| `Cmd` `W` | 탭 닫기 |
| `Cmd` `Shift` `]` 또는 `Cmd` `Shift` `→` | 다음 탭 |
| `Cmd` `Shift` `[` 또는 `Cmd` `Shift` `←` | 이전 탭 |
| `Cmd` `Shift` `O` | 탭을 다른 창으로 옮기기 |

다음/이전 탭은 끝에서 멈춘다. 끝에서 처음으로 돌아가게 하려면 아래
[기본값이 없는 액션](#기본값이-없는-액션)의 `Next tab (cycling)`을 직접 지정한다.

### 창

| 키 | 하는 일 |
|---|---|
| `Cmd` `Shift` `T` | 새 창 |
| `Cmd` `Shift` `W` | 창 닫기 |
| `Cmd` `O` | 다른 창으로 포커스 이동 |

아이패드에서 Split View나 Stage Manager로 Blink를 두 개 띄웠을 때 쓴다.

### 복사와 붙여넣기

| 키 | 하는 일 |
|---|---|
| `Cmd` `C` | 복사 |
| `Cmd` `Shift` `C` | 원본 그대로 복사 (Copy Raw) |
| `Cmd` `V` | 붙여넣기 |

`Cmd` `Shift` `C`는 터미널이 화면에 맞춰 끊어 놓은 줄바꿈을 빼고 원래 텍스트를
가져온다. 긴 명령줄이나 로그를 옮길 때 이쪽을 쓴다.

### 화면

| 키 | 하는 일 |
|---|---|
| `Cmd` `Shift` `=` | 글자 크게 |
| `Cmd` `-` | 글자 작게 |
| `Cmd` `=` | 글자 크기 원래대로 |

### 열기

| 키 | 하는 일 |
|---|---|
| `Cmd` `,` | 설정 (Config) |
| `Cmd` `Shift` `,` | Snippets |
| `Cmd` `Shift` `.` | Scratch (빈 입력창으로 바로 시작) |

Snippets는 저장해 둔 명령 조각을 검색해서 터미널에 넣는 기능이고,
Scratch는 같은 창을 빈 상태로 여는 것이다. 긴 명령을 좁은 터미널에서 고치는
것보다 큰 입력창에서 편집하는 쪽이 편할 때 쓴다.

## Snippets 창 안에서

`Cmd` `Shift` `,` 로 연 검색창에서만 동작한다
(`Blink/Snippets/SearchTextInput.swift`).

| 키 | 하는 일 |
|---|---|
| `↓` / `Ctrl` `N` / `Ctrl` `J` / `Tab` | 다음 항목 |
| `↑` / `Ctrl` `P` / `Ctrl` `K` / `Shift` `Tab` | 이전 항목 |
| `Cmd` `Enter` | 고른 스니펫을 그대로 삽입 |
| `Cmd` `Shift` `C` | 고른 스니펫을 그대로 복사 |
| `Esc` | 닫기 |

## 제스처

키보드 없이 쓸 때의 조작. 모두 소스에서 확인했다
(`Blink/WebKit/WKWebView.swift`, `Blink/SpaceController.swift`).

| 동작 | 하는 일 |
|---|---|
| 두 손가락 탭 | 새 탭 |
| 좌우 스와이프 | 탭 이동 |
| 핀치 | 글자 크기 조절 |
| 한 손가락 탭 | 터미널에 포커스 |
| 길게 누르기 | 텍스트 선택 |
| 화면 아래쪽 가장자리 더블탭 | Quick Actions 메뉴 |

Quick Actions 메뉴에는 Snippets, 탭 닫기, 탭 만들기, 레이아웃, 레이아웃 잠금,
위치 추적 토글이 들어 있다. 기기에 따라 항목이 조금 다르다.

## Smart Keys 바

화면 키보드를 쓸 때 그 위에 붙는 줄이다. `Esc` `Ctrl` `Alt` `Tab` 화살표 등
터미널에 필요한데 iOS 키보드에는 없는 키를 제공한다.

`Ctrl`과 `Alt`는 한 번 누르면 눌린 상태로 유지된다. 실제 키보드의 조합키처럼
`Ctrl`을 누른 채로 여러 키를 이어서 칠 수 있다.

## 단축키 바꾸기

터미널에서 `config`를 치거나 `Cmd` `,` 를 누른다.

```
Config → Keyboard → Shortcuts
```

여기서 액션마다 키 조합을 하나씩 지정한다. 규칙 두 가지가 있다.

- **한 액션에 단축키는 하나만** 지정할 수 있다. 목록에는 아직 안 쓴 액션만 뜬다.
- **기본 단축키는 지우기만 되고 목록에서 없앨 수는 없다.** 비워 두면 그 액션에
  단축키가 없는 상태가 된다.

바꾼 값은 저장하면 바로 적용된다. 예전 버전처럼 앱을 다시 켤 필요는 없다.

## 기본값이 없는 액션

지정할 수 있는 액션은 39개인데 기본 단축키가 붙어 있는 것은 17개뿐이다.
나머지 22개는 위 화면에서 직접 키를 지정해야 쓸 수 있다
(`KB/Native/Model/KeyBindingAction.swift`의 `Command`).

| 액션 | 하는 일 |
|---|---|
| Switch to tab 1 ~ 12 | 번호로 탭 바로 이동 (12개) |
| Next tab (cycling) | 마지막 탭에서 첫 탭으로 넘어감 |
| Previous tab (cycling) | 첫 탭에서 마지막 탭으로 넘어감 |
| Switch to last tab | 마지막 탭으로 |
| Toggle Quick Actions | Quick Actions 메뉴 열고 닫기 |
| Toggle KeyCast | 누른 키를 화면에 표시 (화면 녹화할 때) |
| Hide Keyboard | 화면 키보드 내리기 |
| Google Selection | 선택한 텍스트를 구글에서 검색 |
| StackOverflow Selection | 선택한 텍스트를 Stack Overflow에서 검색 |
| Share Selection | 선택한 텍스트를 공유 시트로 |
| Toggle Geo Track | 위치 추적 켜고 끄기 |

탭 번호 이동을 쓸 거라면 `Cmd` `1` ~ `Cmd` `9` 로 지정하는 것이 무난하다.
macOS 터미널이나 브라우저와 같은 감각이 된다.

## 터미널 키 리매핑

단축키와는 다른 층이다. 단축키가 "Blink 앱에게 시키는 일"이라면, 이쪽은
"터미널에 어떤 바이트를 보낼지"를 정한다.

```
Config → Keyboard → Terminal
```

| 항목 | 흔한 설정 |
|---|---|
| Caps Lock | Esc (vim) 또는 Ctrl (emacs) |
| Shift / Control / Option / Command | 좌우를 따로 지정 가능 |
| Functional Keys | `Fn` 조합으로 F1~F12 보내기 |
| Cursor Keys | 화살표에 붙일 조합키 |
| Custom Presses | 임의의 hex 시퀀스나 문자열 보내기 |

Caps Lock을 Esc로 바꾸는 것이 iOS 기본 키보드 설정으로도 되지만, 여기서 하면
Blink 안에서만 적용된다. 다른 앱에서는 Caps Lock이 그대로 남는다.

`Custom Presses`는 키보드에 없는 문자(`~` `|` `\` `§` `±` 등)나 `Ctrl` `C`
같은 제어 문자를 특정 조합에 붙일 때 쓴다.

### Custom Keyboards

`Config → Keyboard → Blink`에 서드파티 키보드를 막는 스위치가 있다. 터미널에서
예측 입력이나 자동 수정이 끼어드는 게 싫으면 끈다. **이 항목만은 앱을 다시
켜야 적용된다.**

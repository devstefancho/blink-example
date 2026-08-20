> **이 저장소는 [blinksh/blink](https://github.com/blinksh/blink)의 수정본입니다.**
>
> 개인 Apple Developer 계정으로 직접 서명해 아이폰/아이패드에 설치하는 예시입니다.
> 서명이 통과하도록 빌드 설정만 고쳤고 앱 기능은 건드리지 않았습니다.
>
> - 빌드와 설치 방법: [`SETUP.md`](SETUP.md)
> - 단축키와 제스처: [`SHORTCUT.md`](SHORTCUT.md)
>
> **수정 고지 (GPL-3.0 §5(a))**
>
> | | |
> |---|---|
> | 원본 | [blinksh/blink](https://github.com/blinksh/blink) `raw` 브랜치 |
> | 기준 커밋 | `a90b4423c8b7a86770c24a7eaa6c13b0a5904b18` (2026-04-13) |
> | 수정일 | 2026-08-20 |
> | 수정자 | devstefancho |
> | 라이선스 | GPL-3.0 (원본과 동일, [`COPYING`](COPYING)) |
>
> 수정 내용은 빌드 설정 2건과 파일 삭제 2건뿐이며 [`SETUP.md`](SETUP.md#원본과-다른-점)에
> 전부 적어 두었습니다. 소스 코드는 한 줄도 바꾸지 않았습니다.
>
> 이 저장소는 읽기 편하도록 단일 커밋으로 만들었으므로 커밋 이력에
> 원본 기여자들의 기록이 남아 있지 않습니다. Blink Shell의 저작권과 기여 이력은
> 위 원본 저장소에 있으며, 소스 파일별 저작권 고지와 [`AUTHORS`](AUTHORS)는
> 원본 그대로 유지했습니다.
>
> 아래는 원본 Blink Shell의 README입니다.

---

# Blink Shell for iOS
Do Blink! [Blink](https://blink.sh) is the first professional, desktop-grade terminal for iOS that leverages the support of Mosh and SSH. Thus, we can unequivocally guarantee stable connections, lightning-fast speeds, and full configurations. It can and should be your all-day-long tool.

We did not create another terminal to fix your website on the go. Blink was built as a professional grade product from the onset. We started by analyzing what the must-haves were and we ended up grounding Blink on these three concepts:
- Fast rendering: dmesg in your Unix server should be instantaneous. We can't wait even a second to render. We didn't need to reinvent the wheel to make this happen. We simply used Chromium's HTerm to ensure that rendering is perfect and fast, even with those special, tricky encodings.
- Always on: Mosh transcends SSH's variability. Mosh overcomes the unstable and intermittent connectivity that we all associate with mobile connections. You can check your Safari without fear of having to restart the SSH connection. You can flawlessly jump from home, to the train, and then the office thanks to Mosh. Blink is rock-solid connected all the way. Mosh is readily available and can be easily installed on your server. Go to https://mosh.org. 
- Fully configurable: Blink embraces Bluetooth-coupled keyboards with gusto. Some like Caps as Esc on Vim, others Caps as Ctrl on Emacs. Blink champions them all. But there's more, because we want more. You can also add your own custom themes and fonts to Blink. During your always-on sessions, you're in your zone.

But, Blink is much more. Please read on:
- You should command your terminal, not navigate it. Blink will jump you right into a friendly shell and it'll be clear to you how to roll.
- The interface is straightforward. We dumped all menus and went full screen for your terminal.
- Use swipe to move between your open connections, slide down to close them, and even pinch to zoom!
- Configure your Blink connections by adding your own Hosts and RSA Encryption keys. Everything will look familiar and you get to work, fast!
- We've incorporated SplitView, for those necessary Google searches and chats with coworkers.

For more information, please visit [Blink Shell](https://blink.sh).

# Additions: 

Blink also contains a set of shell utilities, so you can add / remove files, list them, etc.

Specifically, the commands available (as of now) are:

* cd, setenv, ls, touch, cp, rm, ln, mv, mkdir, rmdir, 
df, du, chksum, chmod, chflags, chgrp, stat, readlink, 
compress, uncompress, gzip, gunzip,
* pwd, env, printenv, date, uname, id, groups, whoami, uptime
* cat, grep, wc
* curl (includes http, https, scp, sftp...), scp, sftp
* tar 

* You can call commands individually, or use small scripts using python or lua. There is redirection (">", "<", "&>" ...), but no pipe. 

All these commands are inside the `ios_system.framework` (precompiled, for facility). If you want to edit the source (to add more commands), see: https://github.com/holzschu/ios_system. 

curl opens access to file transfers to and from your iPad (ftp, http, scp, sftp...). It uses the key management of BLINKSHELL  (the keys you created with "config"). You can also specify keys with a path:
```
curl scp://host.name.edu/filename -o filename --key $SHARED/id_rsa --pass MyPassword 
```
You can also use the scp and sftp commands:
```
scp user@host.name.edu:filename . 
sftp localFilename user@host.name.edu:~/ 
```

scp and sftp are implemented through curl, by rewriting the arguments to follow the curl syntax. Pro: lighter implementation, smaller memory cost, less likely to have function name collisions. Con: some switches might not have exactly the same meaning. 

# Environment variables

In iOS, because of sandbox restrictions, you cannot write in the `~` directory, only in `~/Documents/`, `~/Library/` and `~/tmp`. Most Unix programs assume the configuration files are in `$HOME`. 
So either you redefine `$HOME` to `~/Documents/` or you set configuration variables (using `setenv`) to some other place.

I do this in Blink, inside the `MCPSession.m` file. The following variables are defined:
```bash
setenv PATH = $PATH:~/Library/bin:~/Documents/bin
setenv PYTHONHOME = $HOME/Library/
setenv SSH_HOME = $HOME/Documents/
setenv CURL_HOME = $HOME/Documents/
setenv HGRCPATH = $HOME/Documents/.hgrc/
setenv SSL_CERT_FILE = $HOME/Documents/cacert.pem
```

If you want to change them permanently, it's probably best to edit `MCPSession.m`.

# Obtaining Blink
Blink is available now on the [AppStore](https://itunes.apple.com/app/id1156707581). Check it out!

If you would like to participate on its development, we would love to have you on board! There are two ways to collaborate with the project: you can download and build Blink yourself, or you can request an invitation to help us test future versions (on the raw branch). If you want to participate on the testing, follow and tweet us [@BlinkShell](https://twitter.com/BlinkShell) about your usage scenarios. Invitations will be sent out in waves, please be patient if you do not receive yours immediately.

Bugs should be reported here on GitHub. If you have any questions or want to make sure we do not miss on an interesting feature, please send your suggestions to our Twitter account [@BlinkShell](https://twitter.com/BlinkShell). We would love to discuss them with you! Please do not use Twitter to report bugs.

We can't wait to receive your valuable feedback. Enjoy!

## Build
![CI](https://github.com/blinksh/blink/workflows/CI/badge.svg)

We made a ton easier to build and install Blink yourself on your iOS devices through XCode. We provide a precompiled package with all the libraries for the master branch. Here are the steps:

0. Check `xcode-select -p` is pointing to Xcode.app (`/Applications/Xcode.app/Contents/Developer`) not command tools.

1. Run the following command:
```bash
git clone --recursive https://github.com/blinksh/blink.git && \
    cd blink && ./get_frameworks.sh && ./get_resources.sh && \
    rm -rf Blink.xcodeproj/project.xcworkspace/xcshareddata/
```

2. Change developer ids

```bash
cp template_setup.xcconfig developer_setup.xcconfig
```

edit developer_setup.xcconfig (change apple developer id etc).

3. Open the project in XCode

3a. If you want to build without iCloud, Push Notificationa and/or Keychain sharing, Before doing anything else, go into the capabilities for the project and turn off Push Notifications, iCloud, and Keychain Sharing

4. Connect the device you want to build for and select it in Product -> Destination
5. Build and run on the device

This will download Blink and the associated frameworks: `libssh2`, `OpenSSL`, `libmoshios`, `protobuf` and `ios_system`. 

Although this is the quickest method to get you up and running, if you would like to compile all libraries and resources yourself, refer to the [BUILD.md](BUILD.md) file. Please let us know if you find any issues. Blink is a complex project with multiple low level dependencies and we are still looking for ways to simplify and automate the full compilation process.

# Using Blink
Our UI is very straightforward and optimizes the experience on touch devices for the really important part, the terminal. You will jump right into a very simple shell, so you will know what to do. Here are a few more tricks:
- Type 'help' to find information at the shell.
- Use two fingers tap to create a new shell.
- Move between shells by swiping your finger.
- You can exit the session and get back to the shell to open a new connection.
- Use pinch gesture to increase or reduce size of text. You can also use Cmd+ or Cmd- if using the keyboard.
- Copy and Paste by selecting text o tapping the screen.
- Run 'config' to setup your keys. Install them to a server through ssh-copy-id.
- Ctrl and Alt modifiers at the SmartKeys bar allow for continuous presses, like in a real keyboard.
- Use 3 finger tap to menu.

# Changelog

[View all changes](CHANGELOG.md)

# Attributions
- [Mosh](https://mosh.org) was written by Keith Winstein, along with Anders Kaseorg, Quentin Smith, Richard Tibbetts, Keegan McAllister, and John Hood.
- This product includes software developed by the OpenSSL Project
for use in the OpenSSL Toolkit. (https://www.openssl.org/).
- [Libssh2](https://www.libssh2.org)
- Entypo pictograms by Bruce Daniel www.entypo.com.

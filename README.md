# Emby 下载

从**你自己的** Emby 服务器把原始媒体文件下载到手机。界面是简体中文。支持 Android 与 iOS。

登录使用官方的 `POST /Users/AuthenticateByName`，请求头为 `X-Emby-Authorization`，密码放在 JSON 字段 `Pw` 里。之后的请求带 `X-Emby-Token`。资料库来自 `GET /Users/{UserId}/Views` 和 `GET /Users/{UserId}/Items`。剧集用 `GET /Shows/{Id}/Seasons` 与 `GET /Shows/{Id}/Episodes`。原始文件优先走 `GET /Items/{Id}/Download`；若服务器返回 400、403 或 404，再试 `GET /Videos/{Id}/stream.{容器}?Static=true`（文档中的不转码直出），最后试 `GET /Items/{Id}/File`。外挂字幕走 `GET /Videos/{Id}/{MediaSourceId}/Subtitles/{Index}/Stream.srt`。内嵌字幕留在原始文件里，不再单独下载。

接口说明以 [Emby REST 文档](https://dev.emby.media/doc/restapi/User-Authentication.html) 和 [视频 / 字幕文档](https://dev.emby.media/doc/restapi/Video-Streaming.html) 为准。

## 功能

- 服务器地址、用户名、密码登录。令牌存在系统密钥库（Android Keystore / iOS Keychain），不保存密码。
- 浏览资料库、海报、搜索、电影详情、剧集 → 季 → 单集。
- 下载原始文件。进度、暂停、继续、取消、队列。可以整季加入队列。有外挂字幕时一并下载。
- Android 下载走前台服务，切到后台可以继续。iOS 使用 `NSURLSession` 后台会话，系统允许时继续。
- 下载页可以播放、删除本地文件。电影和单集详情页有「播放」，在线流和已下载文件都用应用内播放器（media_kit / libmpv）。优先直连原始文件，服务器不允许时改走 PlaybackInfo 返回的 HLS。支持暂停、拖动进度、全屏横屏、音轨、内嵌和外挂字幕，并把播放进度报回 Emby。
- iOS：文件在「文件」App 中可见（`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`）。
- Android：可选「完成后保存到系统下载目录」（`Download/Emby`）。
- 允许明文 HTTP，方便家里的 `http://` 服务器。

## 本地运行

需要 Flutter 3.35（本仓库用 3.35.7 开发）。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Android 安装包：

```bash
flutter build apk --release --split-per-abi
```

产物：

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`：2019 年以后的手机用这个。
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`：更老的 32 位手机。

不要安装同时包含全部 ABI 的通用包，那个会超过 50 MB。工程里的 release 使用 debug 密钥签名，只适合自己安装，不适合上架。

## Android 安装

1. 把 APK 拷到手机。
2. 允许浏览器或文件管理器安装未知来源应用。
3. 打开 APK 安装。
4. 首次下载时允许通知，否则后台任务没有进度通知，长时间下载可能被系统打断。
5. 若打开「保存到系统下载目录」，文件会出现在系统「下载 / Emby」。关闭该选项时，文件在应用私有目录，仍可在下载页播放。

MKV、HEVC 能否播放取决于手机上有没有对应播放器，例如 VLC 或 MX Player。

## iOS：未签名 IPA 与自行签名

本仓库不包含 Apple 证书。CI 用 `flutter build ios --release --no-codesign` 打出**未签名**应用，再打成 IPA：

```text
Payload/Runner.app
```

没有 `embedded.mobileprovision`，也没有代码签名。`tool/pack_unsigned_ipa.sh` 会在检测到签名时直接失败，避免把已签名包当成未签名包。

这台开发环境是 Linux，不能在本地编出 IPA。GitHub Actions 的 `ios-unsigned-ipa` 任务（`macos-latest`）会上传 `emby-downloader-unsigned.ipa`。本地若有 Mac：

```bash
flutter build ios --release --no-codesign
bash tool/pack_unsigned_ipa.sh
```

### Bundle ID

默认是 `app.embydownloader`。

只改这一行即可：

```text
ios/Flutter/AppIdentity.xcconfig
BUNDLE_ID=app.embydownloader
```

Android 应用 ID 在 `android/app/build.gradle.kts` 的 `applicationId`，与 iOS 分开。

描述文件里的 App ID 必须覆盖你最终使用的 Bundle ID。Sideloadly、ESign 也可以在签名时改掉包名；改完之后要和描述文件一致。

### 需要的 entitlement

不需要 Push、iCloud、App Groups、Associated Domains、HealthKit、HomeKit，也不需要自定义 Keychain Access Group。

登录状态使用默认钥匙串（`first_unlock_this_device`，不同步 iCloud）。后台下载是 `NSURLSession` 后台会话，由插件在应用被唤醒时处理 `handleEventsForBackgroundURLSession`。这**不是**描述文件里的 Background Modes 能力，Info.plist 里也没有 `UIBackgroundModes`。

签名工具最好直接采用描述文件里的 entitlement，不要额外合并能力。一份普通的开发或 Ad Hoc 描述文件会写入：

- `application-identifier`（`TEAMID.BundleID`）
- `com.apple.developer.team-identifier`

开发安装通常还有 `get-task-allow`。Ad Hoc 不要带 `get-task-allow`。

如果工具强制要一个 entitlements 文件，用 `ios/Resign.entitlements`，把里面的 `TEAMID` 换成你的 Team ID，并确认 Bundle ID 与描述文件一致。

### Sideloadly

1. 安装 [Sideloadly](https://sideloadly.io/)。
2. 拖入 `emby-downloader-unsigned.ipa`。
3. 填入 Apple ID。Sideloadly 会用这个账号重新签名。
4. 如果描述文件的 Bundle ID 不是 `app.embydownloader`，在高级选项里改成描述文件允许的 ID，或先改 `AppIdentity.xcconfig` 再重新打包。
5. 开始安装。免费 Apple ID 的签名大约 7 天后失效，需要重签。

### ESign

1. 导入 p12 证书和描述文件。
2. 导入未签名 IPA。
3. 签名时选择对应描述文件。不要勾选推送、iCloud、App Groups。
4. 安装签名后的 IPA。

### codesign

从内到外签名。身份字符串用钥匙串里的名称，例如 `Apple Development: Name (TEAMID)`。

```bash
unzip emby-downloader-unsigned.ipa -d resign
# 如需改 Bundle ID：
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.your.bundle' resign/Payload/Runner.app/Info.plist

# 先签嵌入的 framework 和 dylib，再签 .app。
# 不传 entitlements 时，codesign 不会自动从描述文件补 application-identifier。
# 请使用改过 TEAMID 的 ios/Resign.entitlements，或让 fastlane 从描述文件生成。
find resign/Payload/Runner.app -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 |
  xargs -0 -n 1 codesign --force --sign 'Apple Development: Name (TEAMID)'
codesign --force --sign 'Apple Development: Name (TEAMID)' \
  --entitlements ios/Resign.entitlements \
  resign/Payload/Runner.app
cd resign && zip -qry ../emby-downloader-signed.ipa Payload
```

装到设备前还要把描述文件嵌进 `Runner.app/embedded.mobileprovision`，或改用下面的 fastlane，它会一并处理。

### fastlane resign

```bash
fastlane run resign \
  ipa:"emby-downloader-unsigned.ipa" \
  signing_identity:"Apple Development: Name (TEAMID)" \
  provisioning_profile:"/path/to/profile.mobileprovision"
```

不传 `entitlements` 时，fastlane 使用描述文件里的项。这是推荐方式。只有描述文件里的能力和上面列出的基本项不一致时，才传入修改后的 `ios/Resign.entitlements`。

## 服务器端

用户需要有下载权限（Emby 里的 “允许下载媒体” / download 角色）。没有该权限时，`/Items/{Id}/Download` 会失败，应用会改走 `Static=true` 的原始流。若播放权限也没有，下载会失败。

地址示例：`http://192.168.1.10:8096`。末尾的 `/emby` 或 `/web` 可以留着，应用会规范化。

## 限制

这些限制是当前实现的真实行为，不是计划中的功能。

- 没有在真实 Emby 服务器或真机上点过登录和下载。自动化测试覆盖了地址解析、认证请求格式、下载 URL 和登录表单。Android release APK 在本环境编译通过。iOS IPA 需要 macOS CI，本环境编不出来。
- 自签名 HTTPS：登录页的开关只让浏览接口跳过证书校验。后台下载走系统网络栈，正式版不会关闭证书校验。家里的服务器请用 HTTP，或把证书装进系统信任列表。
- 手机连着「已连接但无法访问互联网」的 Wi-Fi 时，Android 的后台任务可能一直停在「等待中」。WorkManager 默认要求网络具备互联网能力。同一 Wi-Fi 能上网、服务器在局域网里时不受影响。
- iOS 后台下载依赖系统调度。把应用从多任务界面划掉，传输可能停止。资源超时设为 24 小时，系统仍可能更早挂起。没有勾选 Background Modes，因此不需要对应的描述文件能力。
- Android 长时间下载依赖前台服务通知。划掉应用或关掉通知后，系统可能停掉任务。
- 下载队列同时进行 2 个任务。令牌写在下载 URL 的 `api_key` 里，这样应用挂起后系统下载器仍能认证。令牌因此会出现在本机的下载任务记录中。
- 只下载外挂字幕。文本字幕转成 `.srt`，和视频放在同一目录，文件名带语言代码。应用内播放会把这些外挂字幕列进字幕菜单；内嵌字幕在直连原始文件时由播放器读取。
- 不支持 Emby Connect。需要能直接访问服务器地址。
- 在线播放的自签名 HTTPS 与后台下载一样，走的是播放器自己的网络栈，不会使用登录页的“信任自签名证书”。家里的服务器请用 HTTP，或把证书装进系统信任列表。
- 应用内播放没有在真机上点过。libmpv 能解 MKV / HEVC，但是否能拖动、切换某条字幕，取决于服务器是否允许原始流以及这份文件本身。

## CI

`.github/workflows/build.yml`

- `android`：`flutter analyze`、`flutter test`，以及按 ABI 拆分的 release APK（arm64-v8a 与 armeabi-v7a）。
- `ios-unsigned-ipa`：`flutter build ios --release --no-codesign`，再打包未签名 IPA。

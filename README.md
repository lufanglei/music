# LX Music for iOS

一个参考 [lx-music-desktop](https://github.com/lyswhut/lx-music-desktop) **自定义音源协议**开发的原生 iPhone 音乐播放器，SwiftUI + AVFoundation + JavaScriptCore，无第三方依赖。

> 官方移动版是 React Native 且明确声明「目前没有计划支持 iOS」。本项目是**独立的第三方实现**，不是官方 iOS 版，与 LX Music 原作者无关联。
>
> 和洛雪一样：**App 本身不提供任何音乐数据**。搜索结果由搜索接口提供，播放链接 `musicUrl` / 歌词 / 封面全部由你导入的 JS 音源脚本返回。

---

## 一、先说清楚交付形态

这里给的是**完整源码 + 可直接双击打开的 Xcode 工程**，外加两条已经配好的 `.ipa` 产出通道（见第三节）。

原因是硬性的：

1. 交付时这台 Mac **只有 Command Line Tools，没有 Xcode、没有 iOS SDK、钥匙串里 0 个签名证书**，因此本机无法编译 arm64 iOS 二进制，也无法产出可安装的包。硬凑一个 zip 改名成 `.ipa` 是假货，不做。
2. iOS App 必须经 Apple 签名才能装进 iPhone，签名需要**你自己的** Apple ID / 证书。任何第三方都无法替你产出「不需要你参与就能装进你手机」的包——这是 iOS 机制，不是工程问题。

好消息是：**云端 macOS 构建机已经把这个工程真实编译成功，并产出了 .ipa** —— 本机文件在 `dist/LXMusic-unsigned-Release.ipa`（553 KB，arm64、未签名），固定下载地址见第三节。所以现在其实**不必再装 Xcode**：拿这个包用侧载工具签名即可。若仍想在本机编译，第三节路径 B 也给出了命令（这台 Mac 还有 179 GB 可用空间，装得下）。

---

## 二、做了什么

### 与洛雪的对应关系

| 洛雪桌面版 | 本工程 |
| --- | --- |
| `LX.Music.MusicInfo` 歌曲模型 | `Models/MusicInfo.swift`，并保留原始 JSON 供脚本读取 `songmid` / `hash` 等平台专有字段 |
| `globalThis.lx` 自定义源 API | `Resources/LXPrelude.js` + `Sources/ScriptEngine.swift` |
| `EVENT_NAMES.inited / request / updateAlert` | ✅ 完整支持 |
| `lx.on` / `lx.send` / `lx.request` | ✅ 支持 `method / headers / body / form / formData / timeout`、取消请求；**原生 URLSession，无浏览器跨域限制** |
| `lx.utils.buffer / crypto / zlib` | ✅ MD5、SHA1、AES-CBC/ECB、RSA(PEM)、randomBytes、Buffer、inflate/deflate |
| `lx.version` / `lx.env` / `lx.currentScriptInfo` | ✅，`lx.env` 默认 `mobile`，可在设置里切 `desktop` 以兼容桌面版脚本 |
| 脚本宿主环境 | 额外补齐 `fetch`、`httpFetch`、`setTimeout/Interval`、`TextEncoder/Decoder`、`Buffer`、`URLSearchParams`、`console`、`btoa/atob` |
| `musicUrl` / `lyric` / `pic` + `qualitys` 音质 | ✅ 按脚本 `inited` 声明分发，音质自动回退 |
| 我的列表 / 播放队列 / 播放模式 | ✅ 本地 JSON 持久化，列表循环 / 单曲循环 / 随机 |
| 歌词 | ✅ LRC 解析、逐行高亮滚动（逐字歌词降级为按行） |
| 播放器 | ✅ AVPlayer 后台播放、锁屏与控制中心信息、耳机线控、来电中断恢复 |
| 桌面版 `musicSdk` 的 kw/kg/tx/wy/mg 内置搜索接口 | ❌ **未内置**（见「已知限制」），改为 Apple 官方曲库 + 自定义 HTTP 搜索接口 |
| 下载 / 数据同步 / 桌面歌词 / 音效均衡器 | ❌ 未实现 |

### 为什么这样设计

我读了桌面版最新源码的 `src/renderer/utils/musicSdk/api-source.js`：**所有内置平台 API 都已被注释掉，现在只走 `userApi` 自定义源**。所以「和落雪一样」的准确含义就是「播放器框架 + 用户导入的音源脚本」，本工程正是按这个分工做的。

原生 iOS 在这里反而有优势：`lx.request` 走 `URLSession`，不受 CORS 限制，音源脚本可以直连各家接口；MD5/AES/RSA 用系统框架实现，脚本里的签名逻辑能原样跑。

### 开箱即用的闭环

首次启动会自动安装内置 **「示例源·Apple 试听」**——它是一份完全符合洛雪规范的音源脚本：

```
搜索 Apple 官方曲库  →  得到 MusicInfo（含原始 previewUrl）
         ↓
点播放 → App 向音源脚本发 EVENT_NAMES.request { action: 'musicUrl', info: {...} }
         ↓
脚本返回 previewUrl  →  AVPlayer 播放官方 30 秒试听
```

这样即使你暂时没有音源，也能立刻验证整条链路。把你自己的洛雪音源脚本导入进去，就能播放对应平台的完整歌曲。

### 目录结构

```
LXMusic-iOS/
├── LXMusic.xcodeproj/
│   ├── project.pbxproj                    # 双击即可打开
│   └── xcshareddata/xcschemes/LXMusic.xcscheme  # 供 xcodebuild -scheme 使用
├── .github/workflows/build-ipa.yml        # 云端编译并上传 .ipa
├── tools/
│   ├── gen_project.py                     # 增删文件后重新生成 pbxproj
│   └── build_ipa.sh                       # 编译 + 打包 .ipa
├── .gitignore
├── README.md
└── LXMusic/
    ├── App/            LXMusicApp.swift、Info.plist（UIBackgroundModes=audio、ATS）
    ├── Models/         MusicInfo / Playlist / SourceCapability / Settings
    ├── Sources/        ScriptEngine、ScriptCrypto、HTTPBridge、SourceManager
    │                   SearchProviders、LocalMusicImporter
    │                   LXPrelude.js（JS 宿主）、DemoSource.js（示例音源）
    ├── Services/       PlayerService、NowPlayingService、AudioSessionManager
    │                   LibraryStore、LyricParser
    ├── Views/          Root / Discover / Library / Player / Settings / Components
    └── Resources/      Assets.xcassets（含 1024×1024 无 alpha 的 AppIcon）
```

---

## 三、拿到 .ipa 文件

### 为什么本机不能直接生成

重新核实过的环境（2026-11-19）：

| 检查项 | 结果 |
| --- | --- |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| `Xcode.app` | 不存在 |
| `xcodebuild` | 不可用（requires Xcode） |
| iPhoneOS SDK | `SDK "iphoneos" cannot be located` |
| 代码签名证书 | `0 valid identities found` |
| 可用磁盘 | 179 GB（装 Xcode 够用） |

### 路径 A：GitHub Actions 云端编译（推荐，无需本机 Xcode）

`.github/workflows/build-ipa.yml` 已配好，macOS runner 自带 Xcode 与 iOS SDK，push 后自动产出 `.ipa` 供下载。

1. 在 GitHub 新建一个**私有仓库**（建议私有，避免公开你后续导入的音源脚本）。
2. 在 `LXMusic-iOS/` 目录执行：

   ```bash
   git init
   git add .
   git commit -m "LX Music iOS"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```

3. 打开仓库 **Actions** 页 → 等 `Build IPA` 跑完 → 点进该次运行 → 底部 **Artifacts** → 下载 `LXMusic-ipa`，解压得到 `LXMusic-unsigned-Release.ipa`。
4. 也可手动触发：Actions → **Build IPA** → **Run workflow**（可选 Debug/Release）。

编译失败时会自动额外上传 `xcodebuild-log`，内含完整错误输出；成功后工作流会校验包内确实存在 `Payload/LXMusic.app/Info.plist`。

> 免费账号的 macOS runner 在私有仓库按分钟计费（公开仓库免费），本工程编译通常只需几分钟。Artifact 默认保留 30 天，需登录 GitHub 下载。

### 固定下载地址（推荐，无需登录）

工作流除了上传 Artifact，还会用 `gh release` 把 .ipa 发布到 tag `ipa-latest`，后续构建用 `--clobber` 覆盖同名文件，地址长期不变：

```
https://github.com/lufanglei/music/releases/download/ipa-latest/LXMusic-unsigned-Release.ipa
```

也可以打开仓库的 **Releases** 页手动下载。本机副本在 `dist/LXMusic-unsigned-Release.ipa`（因每次构建会覆盖同名资产，SHA256 会变化，需要时自行执行 `shasum -a 256` 校验）。

### 路径 B：本机装好 Xcode 后一条命令

从 Mac App Store 安装 Xcode（首次打开需同意许可并装完组件），然后：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd /Users/laylu/workspaces/workbuddy/music/LXMusic-iOS
bash tools/build_ipa.sh                       # 未签名 .ipa
bash tools/build_ipa.sh --team ABCDE12345    # 已签名 .ipa（需开发者 Team ID）
# 可选：--bundle-id com.yourname.lxmusic --configuration Debug --output /tmp
```

产物在 `dist/`，脚本会打印路径、大小、SHA256 和包内结构；完整日志在 `build/xcodebuild.log`，失败时自动摘出错误摘要。

脚本处理了两件容易踩坑的事：

- 传 `CODE_SIGNING_ALLOWED=NO / CODE_SIGNING_REQUIRED=NO / CODE_SIGN_STYLE=Manual`，让没有证书的机器也能编出标准 `Payload/LXMusic.app` 结构的未签名 .ipa
- 用工程内已生成的 **shared scheme `LXMusic`** 构建，避免 `xcodebuild -scheme` 报「Scheme not found」

### .ipa 怎么装进 iPhone

**未签名 .ipa 不能双击或 AirDrop 直接安装**——iOS 要求每个 App 都由证书签名。三种方式：

| 方式 | 需要 | 有效期 |
| --- | --- | --- |
| **Sideloadly / AltStore / 爱思助手（推荐）** | 免费 Apple ID，工具自动重签名 | 7 天，可反复续签 |
| `build_ipa.sh --team` + Xcode / Apple Configurator | Apple ID 或开发者账号 | 免费 7 天 / 付费 1 年 |
| TrollStore / 越狱 | 特定 iOS 版本与漏洞 | 永久 |

Sideloadly 用法：Mac 或 Windows 安装 → 数据线连 iPhone → 拖入 `.ipa` → 填 Apple ID（建议用小号）→ Start。装完在 iPhone **设置 → 通用 → VPN 与设备管理** 里信任该开发者。

#### 侧载报错排查

**`Bundle identifier unavailable: An invalid value '...' was provided for the parameter 'appIdName'`**

Sideloadly / AltStore 在 Apple 后台创建 App ID 时，会把 `Info.plist` 的 `CFBundleDisplayName` 当作 `appIdName` 提交，而 Apple 只接受 ASCII（字母、数字、空格、连字符、下划线、句点）。**中文显示名会直接被拒**——这就是首版包报错的原因。

现已改为全 ASCII 三件套，可直接侧载：

| 字段 | 值 |
| --- | --- |
| `CFBundleDisplayName` | `LX Music` |
| `CFBundleName` | `LXMusic` |
| `CFBundleIdentifier` | `com.lufanglei.lxmusic` |

如果确实想要中文图标名，正确做法是保持 `CFBundleDisplayName` 为 ASCII，另外用 `zh-CN.lproj/InfoPlist.strings` 做本地化；不要把中文直接写进 `CFBundleDisplayName`。

其他常见报错：`The maximum number of App IDs has been reached` 是免费账号的 App ID 数量上限，换一个 Bundle ID 或清理旧 App ID 后重试；`bundle identifier is unavailable` 也可能是该 ID 已被别的账号注册，同样换 ID 即可（`build_ipa.sh --bundle-id` 或改 `gen_project.py` 后重跑）。

---

## 四、用 Xcode 直接装到 iPhone（不经过 .ipa）

如果装好了 Xcode，其实不用打包 .ipa，直接编译安装更简单：

### 准备

- Mac：App Store 安装 **Xcode 15 或更高版本**
- iPhone：iOS 16+，一根数据线
- 一个 Apple ID（免费即可，不需要开发者计划）

### 步骤

1. 双击 `LXMusic.xcodeproj` 用 Xcode 打开。
2. 左侧导航器选中蓝色工程图标 → 中间选 **TARGETS → LXMusic** → **Signing & Capabilities**。
3. 勾选 **Automatically manage signing**；在 **Team** 下拉里选你的 Apple ID。若列表为空：Xcode → Settings… → Accounts → 左下角 `+` → 添加 Apple ID。
4. **Bundle Identifier** 现为 `com.lufanglei.lxmusic`（全局唯一、全 ASCII）。若你的 Apple 账号下已注册过这个 ID，改成别的值即可，例如 `com.<你的名字>.lxmusic`。
5. 用数据线连接 iPhone，解锁，弹窗点「信任此电脑」。
6. Xcode 顶部运行目标从模拟器切到**你的 iPhone**，点 ▶（或 `⌘R`）。
7. 首次安装后打开 App 若提示「不受信任的开发者」：
   iPhone **设置 → 通用 → VPN 与设备管理 → 开发者 App** → 点你的 Apple ID → **信任**。
8. 回到桌面打开「洛雪音乐」。

> 免费 Apple ID 的签名有效期是 **7 天**，过期后连上电脑再点一次 ▶ 即可续期。

### 如果编译报错

CI 首轮编译曾因 `SourceManager.swift:249-250` 把 `String?` / `nil` 赋给非 optional 的 `String` 而失败，已修复（commit `596f8e3`），此后 CI 全绿。本机仍没有 iOS SDK，只做了语法解析和一次受限制的跨文件类型检查（macOS SDK）。若本地 Xcode 报少量适配错误，通常是这几类：

- `JSValue.setObject(block, forKeyedSubscript:)` 提示类型不符 → 把该 block 改成 `unsafeBitCast(block, to: AnyObject.self)` 再传入（`ScriptEngine.installNativeBridge` 里集中处理）。
- SwiftUI 修饰符报「only available in iOS xx」→ 把 `IPHONEOS_DEPLOYMENT_TARGET` 提到对应版本，或换成等价旧 API。
- `CommonCrypto` / `Compression` 常量类型报错 → 这些是 `Int32` / `UInt32`，按报错补 `Int(...)` / `UInt32(...)` 显式转换即可。
- `Signing` 相关报错 → 见上面第 3、4 步；若走 CI 编译则不存在此问题（已关闭签名）。

更省事的做法：按第三节路径 A 跑一次 CI，`xcodebuild-log` 会直接把真实编译错误列出来，改完再 push。

修改源码后若增删了 `.swift` / `.js` 文件，运行 `python3 tools/gen_project.py` 重新生成工程文件即可，不需要手工编辑 pbxproj。

---

## 五、使用

### 导入洛雪音源脚本

**设置 → 自定义音源 → 导入与管理**，三种方式：

- **从 URL 导入脚本**：填音源脚本的在线 `.js` 地址
- **粘贴脚本内容**：直接把脚本文本粘进去
- **从「文件」App 选择 .js**：选本地脚本文件

导入后会自动启用。脚本头部元数据（`@name` / `@description` / `@version` / `@author` / `@homepage`）会按洛雪规则解析，脚本 `inited` 声明的 source、actions、qualitys 会显示在「音源能力」里。

**兼容性提示**：`lx.env` 默认 `mobile`（现有移动版音源脚本占多数）；如果脚本里用 `if (env === 'desktop')` 分支，到「设置 → 播放」切成 `desktop` 再点「应用 env 并重载音源」。

### 搜索来源

- **内置 Apple 曲库**（默认）：iTunes Search API，全球曲库 + 封面 + 官方 30 秒试听，无需密钥、稳定合规。
- **自定义 HTTP 接口**：填 URL 模板，支持 `{keyword}` / `{page}` / `{limit}` 占位符，例如
  `https://your.api/search?keyword={keyword}&page={page}`

返回格式可以是顶层数组，也可以是 `{ "data": [...] }` / `{ "list": [...] }` / `{ "songs": [...] }`。单首歌曲字段：

```json
{
  "name": "歌曲名",
  "singer": "歌手",
  "source": "kw",
  "songId": "123456",
  "songmid": "平台专有 ID",
  "albumName": "专辑",
  "picUrl": "https://example.com/cover.jpg",
  "duration": 235000,
  "qualitys": ["128k", "320k", "flac"]
}
```

字段识别比较宽松（`title/songName`、`artist/artistName`、`id/hash/mid` 等都能识别）。**整个原始对象会原样透传给音源脚本的 `info.musicInfo`**，所以你可以塞任意平台专有字段供脚本签名使用。若接口直接返回 `previewUrl` / `musicUrl` / `url`，即使没有音源也能直接播放。

> `source` 应尽量与音源脚本 `inited` 里声明的 key 对应；对不上时 App 会回退到脚本第一个支持 `musicUrl` 的 source。

### 本地音乐

**我的 → 从「文件」App 导入音频**，支持 MP3 / M4A / FLAC / WAV / AAC 等，会读取内嵌标题、歌手、专辑、封面并复制到 App 沙盒（避免 security-scoped URL 失效）。也可以开启 `UIFileSharingEnabled`，通过 Finder 把音频拖进 App 的 Documents 后点「扫描 Finder 文件共享目录」。

本地歌曲直接走 `AVPlayer` 本地文件，不经过音源脚本。

---

## 六、音源脚本协议速查

完全沿用洛雪官方文档：

```js
/**
 * @name 我的音源
 * @description 说明
 * @version 1.0.0
 * @author xxx
 */
const { EVENT_NAMES, request, on, send, utils, env } = globalThis.lx

on(EVENT_NAMES.request, ({ source, action, info }) => {
  // 必须返回 Promise
  if (action === 'musicUrl') {
    // info = { type: '128k', musicInfo: {...} }
    return Promise.resolve('https://.../song.mp3')
  }
  if (action === 'lyric') {
    // info = { musicInfo: {...} }
    return Promise.resolve({ lyric: '[00:00.00]歌词', tlyric: null, rlyric: null, lxlyric: null })
  }
  if (action === 'pic') return Promise.resolve('https://.../cover.jpg')
  return Promise.reject('action not support')
})

send(EVENT_NAMES.inited, {
  status: true,
  sources: {
    kw: { name: '酷我音乐', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
    local: { name: '本地音乐', type: 'music', actions: ['musicUrl', 'lyric', 'pic'], qualitys: [] },
  },
})
```

`lx.request(url, options, callback)` 的 `resp.body`：若响应是合法 JSON 会解析成对象，否则是字符串；`resp.rawBody` / `resp.bodyString` 始终保留原始字符串。宿主对 `JSON.parse` 做了兼容处理，脚本里写 `JSON.parse(resp.body)` 或直接 `resp.body.url` 都能工作。

---

## 七、校验情况与已知限制

### 已验证

- **iOS 真机编译与链接已通过**：GitHub Actions（`macos-15` / Xcode 16.4 / iPhoneOS 18.5 SDK）完整构建成功，`LXMusic` 可执行文件为 `Mach-O 64-bit executable arm64`
- **.ipa 包结构已校验**：标准 `Payload/LXMusic.app/`，含 `Info.plist`、`LXMusic`、`Assets.car`、`LXPrelude.js`、`DemoSource.js`、`AppIcon*.png`；显示名 `LX Music`、Bundle ID `com.lufanglei.lxmusic`，均为 ASCII（侧载工具创建 App ID 不会报 `appIdName` 非法）
- 21 个 Swift 文件全部通过 `swiftc -frontend -parse` 语法解析
- 跨文件 `swiftc -typecheck`（macOS SDK）：仅报 `no such module 'UIKit'`（iOS 专属模块，属预期假阳性），在可解析范围内未发现跨文件引用或类型错误
- `project.pbxproj` 通过 `plutil -lint`，76 个对象无悬空引用，21 个源文件全部进入 Sources 阶段，资源与 3 个系统框架齐全
- 新增的 shared scheme 通过 XML 解析校验；`tools/build_ipa.sh` 通过 `bash -n`；CI 工作流 YAML 结构完整
- `Info.plist` 通过 `plutil -lint`（含 `UIBackgroundModes = audio`、ATS 例外）
- AppIcon 已扁平化为 **1024×1024 RGB 无 alpha**，符合 `actool` 对 App Store 图标的要求（原 RGBA 会导致编译期图标校验报错）
- `LXPrelude.js` / `DemoSource.js` 通过 `node --check`
- **用 Node 模拟 `globalThis.lx` 跑了一份标准洛雪音源脚本**：`inited` 事件、`request → musicUrl` 的 Promise 解析、`lyric` action、`fetch().json()`、MD5、TextEncoder、URLSearchParams、zlib、定时器全部通过

### 未验证 / 已知限制

- **未在 iPhone 真机安装运行、未跑模拟器**：编译与链接已在 CI 通过，但运行时行为（音源脚本执行、后台播放、锁屏控制、音频中断恢复）仍需真机验证。这是当前交付最主要的残留风险。
- 本机仍无 Xcode / iOS SDK，无法本地编译；需要本机编译请先装 Xcode（路径 B）。
- CI 与本机脚本产出的是**未签名** .ipa，必须经侧载工具或你自己的证书重签名才能安装。
- 未内置桌面版 `musicSdk` 里 kw/kg/tx/wy/mg 的搜索接口：那些接口带平台私有加密签名、变动频繁且涉及版权合规，不适合原样搬进一个未签名的本地工程。需要的话请通过「自定义 HTTP 搜索接口」指向你自建的服务，或自行在 `SearchProviders.swift` 增加 Provider。
- 未实现下载、多端数据同步、桌面歌词、音效均衡器、歌单/排行榜详情页。
- `XMLHttpRequest`、`Worker`、`crypto.subtle` 未提供；绝大多数音源脚本用 `lx.request` / `fetch`，如需可自行在 `LXPrelude.js` 补。
- iOS PWA 常见的后台限制在这里不存在（原生 audio 后台模式 + 远程控制已配置），但**锁屏切歌需要 App 至少成功播放过一次**才能注册远程控制。
- 示例源播放的是 Apple 官方 30 秒试听，不是完整歌曲；完整播放请导入你自己的音源。

---

## 八、协议与免责

- 原项目基于 **Apache License 2.0**，并附有补充协议（数据来源、24 小时内清除版权数据、非商业性质、尊重版权等），使用本项目时同样应当遵守，原文见 [lx-music-desktop README](https://github.com/lyswhut/lx-music-desktop#项目协议)。
- 本项目仅用于**技术可行性探索与学习研究**，不提供、不托管、不缓存任何音乐文件，不接受任何商业合作与捐赠。
- 请只导入你信任的音源脚本：脚本在 App 内的 JSContext 中运行，具备网络请求能力。
- 音乐平台不易，请尊重版权、支持正版。

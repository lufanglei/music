#!/usr/bin/env bash
# LX Music for iOS — 编译并打包成 .ipa
#
# 用法:
#   bash tools/build_ipa.sh                      # 未签名 .ipa（默认，供侧载工具重签名）
#   bash tools/build_ipa.sh --team ABCDE12345   # 用 Apple Developer Team 自动签名
#   bash tools/build_ipa.sh --team ABCDE12345 --bundle-id com.yourname.lxmusic
#   bash tools/build_ipa.sh --configuration Debug
#
# 产物默认放在 dist/ 目录。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="LXMusic.xcodeproj"
SCHEME="LXMusic"
CONFIG="Release"
MODE="unsigned"
TEAM=""
BUNDLE_ID=""
OUT="$ROOT/dist"
BUILD="$ROOT/build"

usage() {
  cat <<'EOF'
用法: bash tools/build_ipa.sh [选项]

  --unsigned                 产出未签名 .ipa（默认）
  --team <TEAM_ID>           用指定 Developer Team 自动签名后打包
  --bundle-id <ID>           覆盖 PRODUCT_BUNDLE_IDENTIFIER
  --configuration <NAME>     Debug 或 Release（默认 Release）
  --output <DIR>             产物目录（默认 dist/）
  -h, --help                 显示帮助

说明: 未签名 .ipa 不能直接装进 iPhone，需用 Sideloadly / AltStore /
      爱思助手等工具输入你自己的 Apple ID 重新签名；或装上 Xcode 后
      用 --team 直接产出已签名版本。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned)      MODE="unsigned"; shift ;;
    --team)          MODE="signed"; TEAM="${2:?--team 需要一个 Team ID}"; shift 2 ;;
    --bundle-id)     BUNDLE_ID="${2:?--bundle-id 需要一个 Bundle ID}"; shift 2 ;;
    --configuration) CONFIG="${2:?--configuration 需要一个值}"; shift 2 ;;
    --output)        OUT="${2:?--output 需要一个目录}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               printf '未知参数: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---- 环境预检：这里是最常见的失败原因 -------------------------------------
if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  cat >&2 <<'EOF'
错误: 未检测到完整 Xcode（当前只有 Command Line Tools）。

xcodebuild 需要 /Applications/Xcode.app，请任选其一:
  1. 从 Mac App Store 安装 Xcode，然后执行
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  2. 或者把本工程推到 GitHub，用 .github/workflows/build-ipa.yml
     在 macOS 云构建机上编译并直接下载 .ipa（无需本机 Xcode）。
EOF
  exit 3
fi

if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  printf '错误: 找不到 iPhoneOS SDK，请确认 Xcode 已完整安装并首次启动过。\n' >&2
  exit 3
fi

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  printf '错误: 找不到 %s，请在工程根目录运行本脚本。\n' "$PROJECT" >&2
  exit 3
fi

printf 'Xcode  : %s\n' "$(xcodebuild -version | tr '\n' ' ')"
printf 'iOS SDK: %s\n' "$(xcrun --sdk iphoneos --show-sdk-path)"
printf '配置   : %s / %s\n\n' "$CONFIG" "$MODE"

mkdir -p "$OUT" "$BUILD"
DERIVED="$BUILD/DerivedData"
APP_DIR="$DERIVED/Build/Products/$CONFIG-iphoneos"
LOG="$BUILD/xcodebuild.log"

COMMON=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -sdk iphoneos
  -derivedDataPath "$DERIVED"
  -destination 'generic/platform=iOS'
)

if [[ "$MODE" == "unsigned" ]]; then
  SIGN_ARGS=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=""
  )
  if [[ -n "$BUNDLE_ID" ]]; then
    SIGN_ARGS+=( "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" )
  fi
else
  SIGN_ARGS=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Automatic
    "DEVELOPMENT_TEAM=$TEAM"
    -allowProvisioningUpdates
  )
  if [[ -n "$BUNDLE_ID" ]]; then
    SIGN_ARGS+=( "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" )
  fi
fi

printf '开始编译，日志: %s\n' "$LOG"
set +e
xcodebuild "${COMMON[@]}" "${SIGN_ARGS[@]}" clean build 2>&1 | tee "$LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  printf '\n编译失败（xcodebuild 退出码 %s）。完整日志见 %s\n' "$BUILD_STATUS" "$LOG" >&2
  printf '错误摘要:\n' >&2
  grep -E "error:|fatal error:|warning: .*deprecated" "$LOG" | head -40 >&2 || true
  exit 4
fi

APP="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' 2>/dev/null | head -n 1 || true)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  printf '错误: 在 %s 下没有找到 .app 产物。\n' "$APP_DIR" >&2
  exit 4
fi

# ---- 打包成标准 .ipa（Payload/xxx.app）------------------------------------
STAGE="$BUILD/Payload"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

IPA="$OUT/LXMusic-${MODE}-${CONFIG}.ipa"
rm -f "$IPA"
( cd "$BUILD" && zip -qry "$IPA" Payload -x '*.DS_Store' )

printf '\n========== 构建完成 ==========\n'
printf '产物 : %s\n' "$IPA"
printf '大小 : %s\n' "$(du -h "$IPA" | cut -f1)"
printf 'SHA256: %s\n' "$(shasum -a 256 "$IPA" | cut -d' ' -f1)"
printf '\n包内结构:\n'
unzip -Z1 "$IPA" | head -12

if [[ "$MODE" == "unsigned" ]]; then
  cat <<'EOF'

注意: 这是【未签名】.ipa，iPhone 不能直接安装。
请用 Sideloadly / AltStore / 爱思助手 打开它并输入你自己的 Apple ID
完成重签名后安装（免费账号有效期 7 天，可重复续签）。
EOF
else
  printf '\n已使用 Team %s 签名，可通过 Xcode / Apple Configurator 安装。\n' "$TEAM"
fi

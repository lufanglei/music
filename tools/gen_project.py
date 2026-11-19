#!/usr/bin/env python3
"""
生成 LXMusic.xcodeproj/project.pbxproj 与 AppIcon.png。

工程不依赖 XcodeGen / CocoaPods / SwiftPM：全部源码与资源用标准 pbxproj 描述，
装好 Xcode 后双击 LXMusic.xcodeproj 即可编译。
若后续增删了 .swift / .js 文件，重新运行本脚本即可刷新工程文件。
"""
import hashlib
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "LXMusic.xcodeproj")
SOURCE_ROOT = os.path.join(ROOT, "LXMusic")


def oid(kind, path):
    digest = hashlib.md5((kind + ":" + path).encode("utf-8")).hexdigest()
    return digest[:24].upper()


FIXED = {
    "project": "100000000000000000000001",
    "target": "100000000000000000000002",
    "mainGroup": "100000000000000000000003",
    "productsGroup": "100000000000000000000004",
    "product": "100000000000000000000005",
    "sourcesPhase": "100000000000000000000006",
    "resourcesPhase": "100000000000000000000007",
    "frameworksPhase": "100000000000000000000008",
    "projectConfigList": "100000000000000000000009",
    "targetConfigList": "10000000000000000000000A",
    "projectDebug": "10000000000000000000000B",
    "projectRelease": "10000000000000000000000C",
    "targetDebug": "10000000000000000000000D",
    "targetRelease": "10000000000000000000000E",
}

FRAMEWORKS = ["JavaScriptCore.framework", "AVFoundation.framework", "MediaPlayer.framework"]

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".js": "text.javascript",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
}


def collect():
    swift, resources, plists, assets = [], [], [], []
    for dirpath, dirnames, filenames in os.walk(SOURCE_ROOT):
        dirnames[:] = [d for d in dirnames if not d.endswith(".xcassets")]
        for name in sorted(filenames):
            rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
            ext = os.path.splitext(name)[1]
            if ext == ".swift":
                swift.append(rel)
            elif ext == ".js":
                resources.append(rel)
            elif ext == ".plist":
                plists.append(rel)
    assets.append(os.path.relpath(
        os.path.join(SOURCE_ROOT, "Resources", "Assets.xcassets"), ROOT))
    return swift, resources, plists, assets


def q(text):
    """pbxproj 字符串：只在必要时加引号"""
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./$-")
    if text and all(c in safe for c in text):
        return text
    return '"' + text.replace('"', '\\"') + '"'


def build():
    swift, resources, plists, assets = collect()
    lines = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # ---- PBXBuildFile ----
    add("")
    add("/* Begin PBXBuildFile section */")
    for rel in swift + resources + assets:
        name = os.path.basename(rel)
        add("\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (
            oid("build", rel), name,
            "Sources" if rel.endswith(".swift") else "Resources",
            oid("ref", rel), name))
    for fw in FRAMEWORKS:
        add("\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (
            oid("buildfw", fw), fw, oid("reffw", fw), fw))
    add("/* End PBXBuildFile section */")

    # ---- PBXFileReference ----
    add("")
    add("/* Begin PBXFileReference section */")
    all_files = swift + resources + plists + assets
    for rel in all_files:
        name = os.path.basename(rel)
        ftype = FILE_TYPES[os.path.splitext(name)[1]]
        add("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };" % (
            oid("ref", rel), name, ftype, q(name)))
    for fw in FRAMEWORKS:
        add("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = %s; path = System/Library/Frameworks/%s; sourceTree = SDKROOT; };" % (
            oid("reffw", fw), fw, fw, fw))
    add("\t\t%s /* LXMusic.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LXMusic.app; sourceTree = BUILT_PRODUCTS_DIR; };" % FIXED["product"])
    add("/* End PBXFileReference section */")

    # ---- PBXFrameworksBuildPhase ----
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    add("\t\t%s /* Frameworks */ = {" % FIXED["frameworksPhase"])
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for fw in FRAMEWORKS:
        add("\t\t\t\t%s /* %s in Frameworks */," % (oid("buildfw", fw), fw))
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # ---- PBXGroup ----
    add("")
    add("/* Begin PBXGroup section */")
    groups = {}
    for rel in all_files:
        parts = rel.split(os.sep)
        for depth in range(1, len(parts)):
            groups.setdefault(os.sep.join(parts[:depth]), set())
        if len(parts) > 1:
            groups[os.sep.join(parts[:-1])].add(rel)

    add("\t\t%s /* Main Group */ = {" % FIXED["mainGroup"])
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add("\t\t\t\t%s /* LXMusic */," % oid("group", "LXMusic"))
    add("\t\t\t\t%s /* Products */," % FIXED["productsGroup"])
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    for group_path in sorted(groups, key=lambda p: (p.count(os.sep), p)):
        gid = oid("group", group_path)
        name = os.path.basename(group_path)
        add("\t\t%s /* %s */ = {" % (gid, name))
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        children = []
        # 子目录
        for candidate in sorted(groups):
            if os.path.dirname(candidate) == group_path:
                children.append((os.path.basename(candidate), oid("group", candidate)))
        # 文件
        for rel in sorted(groups[group_path]):
            children.append((os.path.basename(rel), oid("ref", rel)))
        for child_name, child_id in children:
            add("\t\t\t\t%s /* %s */," % (child_id, child_name))
        add("\t\t\t);")
        add("\t\t\tpath = %s;" % q(name))
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")

    add("\t\t%s /* Products */ = {" % FIXED["productsGroup"])
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add("\t\t\t\t%s /* LXMusic.app */," % FIXED["product"])
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")
    add("/* End PBXGroup section */")

    # ---- PBXNativeTarget ----
    add("")
    add("/* Begin PBXNativeTarget section */")
    add("\t\t%s /* LXMusic */ = {" % FIXED["target"])
    add("\t\t\tisa = PBXNativeTarget;")
    add("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"LXMusic\" */;" % FIXED["targetConfigList"])
    add("\t\t\tbuildPhases = (")
    add("\t\t\t\t%s /* Sources */," % FIXED["sourcesPhase"])
    add("\t\t\t\t%s /* Frameworks */," % FIXED["frameworksPhase"])
    add("\t\t\t\t%s /* Resources */," % FIXED["resourcesPhase"])
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add("\t\t\tname = LXMusic;")
    add("\t\t\tproductName = LXMusic;")
    add("\t\t\tproductReference = %s /* LXMusic.app */;" % FIXED["product"])
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # ---- PBXProject ----
    add("")
    add("/* Begin PBXProject section */")
    add("\t\t%s /* Project object */ = {" % FIXED["project"])
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    add("\t\t\t\tLastUpgradeCheck = 1600;")
    add("\t\t\t\tTargetAttributes = {")
    add("\t\t\t\t\t%s = {" % FIXED["target"])
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"LXMusic\" */;" % FIXED["projectConfigList"])
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t\t\"zh-Hans\",")
    add("\t\t\t);")
    add("\t\t\tmainGroup = %s;" % FIXED["mainGroup"])
    add("\t\t\tproductRefGroup = %s /* Products */;" % FIXED["productsGroup"])
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add("\t\t\t\t%s /* LXMusic */," % FIXED["target"])
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # ---- PBXResourcesBuildPhase ----
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add("\t\t%s /* Resources */ = {" % FIXED["resourcesPhase"])
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for rel in resources + assets:
        add("\t\t\t\t%s /* %s in Resources */," % (oid("build", rel), os.path.basename(rel)))
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # ---- PBXSourcesBuildPhase ----
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add("\t\t%s /* Sources */ = {" % FIXED["sourcesPhase"])
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for rel in swift:
        add("\t\t\t\t%s /* %s in Sources */," % (oid("build", rel), os.path.basename(rel)))
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # ---- XCBuildConfiguration ----
    add("")
    add("/* Begin XCBuildConfiguration section */")
    project_common = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CODE_SIGN_STYLE = Automatic;",
        "DEVELOPMENT_TEAM = \"\";",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu17;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "IPHONEOS_DEPLOYMENT_TARGET = 16.0;",
        "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
        "SDKROOT = iphoneos;",
        "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";",
        "SWIFT_STRICT_CONCURRENCY = minimal;",
        "SWIFT_VERSION = 5.0;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]
    target_common = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = 1;",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = LXMusic/App/Info.plist;",
        "IPHONEOS_DEPLOYMENT_TARGET = 16.0;",
        "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");",
        "MARKETING_VERSION = 1.0.0;",
        "PRODUCT_BUNDLE_IDENTIFIER = com.lufanglei.lxmusic;",
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "SWIFT_STRICT_CONCURRENCY = minimal;",
        "SWIFT_VERSION = 5.0;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]

    configs = [
        (FIXED["projectDebug"], "Debug", project_common + [
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "GCC_OPTIMIZATION_LEVEL = 0;",
            "GCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\");",
            "ONLY_ACTIVE_ARCH = YES;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";",
            "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
        ]),
        (FIXED["projectRelease"], "Release", project_common + [
            "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
            "ENABLE_NS_ASSERTIONS = NO;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
            "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
            "VALIDATE_PRODUCT = YES;",
        ]),
        (FIXED["targetDebug"], "Debug", target_common + [
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
        ]),
        (FIXED["targetRelease"], "Release", target_common + [
            "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
            "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
        ]),
    ]
    for cid, name, settings in configs:
        add("\t\t%s /* %s */ = {" % (cid, name))
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for setting in settings:
            add("\t\t\t\t%s" % setting)
        add("\t\t\t};")
        add("\t\t\tname = %s;" % name)
        add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList ----
    add("")
    add("/* Begin XCConfigurationList section */")
    for cid, label, debug, release in [
        (FIXED["projectConfigList"], "PBXProject \"LXMusic\"", FIXED["projectDebug"], FIXED["projectRelease"]),
        (FIXED["targetConfigList"], "PBXNativeTarget \"LXMusic\"", FIXED["targetDebug"], FIXED["targetRelease"]),
    ]:
        add("\t\t%s /* Build configuration list for %s */ = {" % (cid, label))
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add("\t\t\t\t%s /* Debug */," % debug)
        add("\t\t\t\t%s /* Release */," % release)
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add("\trootObject = %s /* Project object */;" % FIXED["project"])
    add("}")
    add("")

    os.makedirs(PROJECT_DIR, exist_ok=True)
    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return swift, resources, assets


# --------------------------------------------------------------- AppIcon.png

def make_icon(path):
    # App Store / actool 要求 1024x1024 图标不带 alpha 通道，
    # 因此这里直接输出 color type 2 (RGB) 的 PNG，而不是 RGBA。
    size = 1024
    rows = []
    for y in range(size):
        row = bytearray()
        t = y / (size - 1)
        for x in range(size):
            u = (x / (size - 1) * 0.55 + t * 0.45)
            r = int(46 + (123 - 46) * u)
            g = int(91 + (77 - 91) * u)
            b = int(255 - (255 - 250) * u)
            row += bytes((r, g, b))
        rows.append(row)

    def fill_rect(x0, y0, x1, y1, color):
        for yy in range(max(0, y0), min(size, y1)):
            rows[yy][max(0, x0) * 3:min(size, x1) * 3] = color * (min(size, x1) - max(0, x0))

    def fill_ellipse(cx, cy, rx, ry, color):
        for yy in range(max(0, cy - ry), min(size, cy + ry)):
            for xx in range(max(0, cx - rx), min(size, cx + rx)):
                if ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0:
                    rows[yy][xx * 3:xx * 3 + 3] = color

    white = bytes((255, 255, 255))
    # 两个符干
    fill_rect(470, 265, 512, 730, white)
    fill_rect(690, 225, 732, 690, white)
    # 连接横梁（略带倾斜）
    for yy in range(225, 305):
        shift = int((yy - 225) * 0.18)
        fill_rect(470 + shift, yy, 732 + shift, yy + 1, white)
    # 两个符头
    fill_ellipse(392, 720, 100, 72, white)
    fill_ellipse(612, 680, 100, 72, white)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    swift_files, resource_files, asset_files = build()
    icon = os.path.join(SOURCE_ROOT, "Resources", "Assets.xcassets",
                        "AppIcon.appiconset", "AppIcon.png")
    make_icon(icon)
    print("已生成 project.pbxproj")
    print("Swift 源文件: %d" % len(swift_files))
    print("资源文件: %d" % len(resource_files))
    print("Asset Catalog: %d" % len(asset_files))
    print("AppIcon: %s" % icon)

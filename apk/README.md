# apk/ — Android TWA 壳应用

基于 [Trusted Web Activity (TWA)](https://developer.chrome.com/docs/android/trusted-web-activity/) 技术的 Android 壳应用，用于将 rlbox Web 应用打包成原生 APK。

由 [Bubblewrap](https://github.com/GoogleChromeLabs/bubblewrap) 生成，已清除所有业务相关的硬编码，改为占位符系统。克隆后运行一条命令即可初始化为你自己的 App。

---

## 前置要求

| 工具 | 版本要求 | 说明 |
|------|---------|------|
| JDK | 17+ | `java -version` 确认 |
| Android SDK | API 33+ | 需要 `build-tools` 和 `platform-tools` |
| Python | 3.10+ | 用于 setup / gen_icons / build 脚本 |
| Pillow | 任意 | 图标生成依赖，`pip install Pillow` |

> **注意**：`./gradlew` 会自动下载对应版本的 Gradle，无需手动安装。

---

## 快速开始

### 第一步：初始化配置

从项目根目录运行（不要 `cd apk/`）：

```bash
python3 apk/bin/setup
```

脚本会交互式询问 4 个参数：

```
1. Package ID       例: com.example.myapp
2. 应用名称          例: MyApp
3. 主题色（Hex）     例: #3B82F6
4. 应用域名          例: app.example.com
```

完成后，脚本自动完成：
- ✅ 替换全部文件中的 45 处占位符
- ✅ 重命名 Java 包目录（`ai/clacky/rlbox/` → `com/example/myapp/`）

### 第二步：替换应用图标

准备一张 **512×512 的正方形 PNG**，复制到：

```bash
cp your-logo.png apk/store_icon.png
```

### 第三步：生成所有图标尺寸

```bash
python3 apk/bin/gen_icons
```

脚本会自动生成 20 个不同尺寸的图标，覆盖 `apk/app/src/main/res/` 下对应目录。

### 第四步：构建 APK

推荐用统一的 `build` 脚本，一条命令搞定 debug/release：

```bash
apk/bin/build                  # debug 版（默认，用 Android SDK 自带 debug 签名）
apk/bin/build --release        # release 版（需 app/build.gradle 配好 signingConfigs.release）
apk/bin/build --release --install    # 打包后自动 adb install -r 到当前 emulator
apk/bin/build --clean --release      # 先 clean 再打
```

脚本会：
1. 调 `./gradlew assemble<Debug|Release>` 打包
2. 把产物复制到 `apk/<slug>-<variant>.apk`（slug 取自 `applicationId` 最后一段），方便分发
3. `--install` 传入时还会 `adb install -r` 到当前在线设备

产物位置：

| 变体 | Gradle 原始产物 | 复制后（方便分发） |
|---|---|---|
| debug | `apk/app/build/outputs/apk/debug/app-debug.apk` | `apk/<slug>-debug.apk` |
| release | `apk/app/build/outputs/apk/release/app-release.apk` | `apk/<slug>-release.apk` |

> **release 版前置**：`app/build.gradle` 里要有 `signingConfigs.release` 指向一个真实 keystore。
> 生成 keystore 示例：
> ```bash
> keytool -genkey -v -keystore apk/android.keystore \
>   -alias android -keyalg RSA -keysize 2048 -validity 10000 \
>   -storepass <PWD> -keypass <PWD> \
>   -dname 'CN=app, O=org, C=CN'
> ```
> 然后把密码写到 `app/build.gradle` 的 `signingConfigs.release { storePassword '<PWD>'; keyPassword '<PWD>'; storeFile file('../android.keystore'); keyAlias 'android' }`。
> `apk/android.keystore` 和密码**不要提交到公开仓库**，走私有仓库或 CI secrets。

---

## 占位符说明

模板仓库中存的是以下占位符，`setup` 脚本会统一替换：

| 占位符 | 含义 | 示例值 |
|--------|------|--------|
| `RLBOX_PACKAGE_ID` | Android 包名 | `com.example.myapp` |
| `RLBOX_APP_NAME` | 应用显示名称 | `MyApp` |
| `RLBOX_THEME_COLOR` | 主题色（状态栏颜色） | `#3B82F6` |
| `RLBOX_HOST` | 应用域名（不含 `https://`） | `app.example.com` |
| `RLBOX_API_KEY_PREFIX` | Settings.Global 键前缀（一般 = app slug，用于区分多 APK 装同一设备时的 adb 配置） | `myapp`（生成 `myapp_api_endpoint` 等键） |

涉及的文件共 10 个：

```
apk/
├── twa-manifest.json
├── app/
│   ├── build.gradle
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── res/
│       │   ├── values/strings.xml
│       │   └── raw/web_app_manifest.json
│       └── java/<package-path>/
│           ├── Application.java
│           ├── ConfigHelper.java
│           ├── CustomWebViewFallbackActivity.java
│           ├── DelegationService.java
│           └── LauncherActivity.java
```

---

## 图标文件说明

`gen_icons` 脚本从 `apk/store_icon.png` 生成以下 20 个文件：

| 类型 | 用途 | 尺寸（mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi） |
|------|------|----------------------------------------|
| `ic_launcher.png` | 应用图标 | 48 / 72 / 96 / 144 / 192 |
| `ic_maskable.png` | 自适应图标 | 82 / 123 / 164 / 246 / 328 |
| `splash.png` | 启动屏图标 | 300 / 450 / 600 / 900 / 1200 |
| `ic_notification_icon.png` | 通知栏图标 | 24 / 36 / 48 / 72 / 96 |

---

## 签名说明

仓库中已包含 `android.keystore`（从 fliggy 迁移而来）。构建时 Gradle 会自动使用它对 APK 进行签名。

如需使用自己的 keystore：

1. 生成新 keystore：
   ```bash
   keytool -genkey -v -keystore android.keystore \
     -alias android -keyalg RSA -keysize 2048 -validity 10000
   ```

2. 更新 `app/build.gradle` 中的签名配置：
   ```groovy
   signingConfigs {
       release {
           storeFile file('../android.keystore')
           storePassword 'your-store-password'
           keyAlias 'your-key-alias'
           keyPassword 'your-key-password'
       }
   }
   ```

> ⚠️ **重要**：keystore 一旦用于上架 Google Play，就不能更换，否则无法更新应用。请妥善备份。

---

## 常见问题

**Q: `./gradlew assembleRelease` 报 SDK not found？**

设置 `ANDROID_HOME` 环境变量：
```bash
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools
```

**Q: setup 脚本提示 Package ID 格式错误？**

包名需满足：至少两段、每段只含字母/数字/下划线、不以数字开头。例如 `com.myapp` ✅，`myapp` ❌，`com.123app` ❌。

**Q: 主题色支持哪些格式？**

支持 `#RGB`、`#RRGGBB`、`#AARRGGBB` 三种格式，如 `#F00`、`#FF0000`、`#FFFF0000`。

**Q: 运行 gen_icons 提示缺少 Pillow？**

```bash
pip install Pillow
# 或
apt-get install python3-pil
```

**Q: 想重新初始化（改包名/颜色）怎么办？**

`setup` 脚本只会替换占位符，如果已经运行过一次，需要先从模板重新 checkout：
```bash
git checkout -- apk/
python3 apk/bin/setup
```

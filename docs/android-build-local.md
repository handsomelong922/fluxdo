# Android 打包与长期更新

如果你后期要长期追上游，并且希望新 APK 能直接覆盖你之前安装的版本，最重要的不是 Firebase，而是下面两件事始终不变：

- `applicationId` 保持一致
- 发布签名 keystore 保持一致

当前项目的 Android 包名在 [`android/app/build.gradle.kts`](D:/Edge浏览器下载/Cloud%20files/OneDrive%20-%20cmu.edu.cn/Document/杂项备份/n8n工作流/工作区2/fluxdo/android/app/build.gradle.kts) 里是：

```text
com.github.lingyan000.fluxdo
```

只要你以后继续使用同一个包名、同一个 keystore，后续新包就可以覆盖你自己之前安装的旧包。

注意：你作为 fork，无法覆盖“上游作者签名”的安装包。你只能稳定覆盖“你自己签名”的安装包。

## 先看当前仓库状态

- 仓库里已经有 `android/app/google-services.json`
- 仓库里已经有 `android/key.properties.template`
- 现在最容易卡住的是本机没有 Flutter / Java / Android SDK，以及没有发布签名文件

## 正规推荐路径

推荐从一开始就按 release 签名流程走，不要把 debug 包当长期更新渠道。

你需要长期保存这两个本地文件：

- `android/app/upload-keystore.jks`
- `android/key.properties`

其中 `android/key.properties` 的模板已经在仓库里：

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=upload-keystore.jks
```

如果是 Windows，可以用仓库里的脚本来生成和导出 GitHub secrets：

```powershell
.\scripts\setup_android_release_signing.ps1
```

这个脚本会在本机已安装 JDK 17 的前提下：

1. 生成 `android/app/upload-keystore.jks`
2. 生成 `android/key.properties`
3. 导出 `ANDROID_KEYSTORE_BASE64`
4. 导出 `ANDROID_KEY_PROPERTIES`
5. 如果需要，也会导出 `GOOGLE_SERVICES_JSON`

## 本地构建

1. 安装 Flutter
2. 安装 Android Studio，并确认带上 Android SDK、Platform Tools、Command-line Tools
3. 安装 JDK 17
4. 在仓库根目录执行：

```powershell
flutter pub get
.\scripts\build_android.ps1
flutter build apk --debug --dart-define=cronetHttpNoPlay=true
```

调试包通常会输出到：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

如果你只是先验证能跑起来，可以先用调试包。

如果你已经准备好了 release keystore，则可以继续尝试：

```powershell
flutter build apk --release --dart-define=cronetHttpNoPlay=true
```

正式包通常会输出到：

```text
build\app\outputs\flutter-apk\app-release.apk
```

## 什么时候才需要 keystore

只有你要打“正式发布 APK”或沿用 GitHub Actions release 流程时，才需要：

- `android/key.properties`
- `android/app/upload-keystore.jks`

仓库里的 `android/key.properties.template` 就是模板，内容如下：

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=upload-keystore.jks
```

## GitHub Actions release 流程

当前 `.github/workflows/build.yaml` 的 Android 签名步骤会读取这些 secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_PROPERTIES`
- `GOOGLE_SERVICES_JSON`

现在 workflow 已经允许 `GOOGLE_SERVICES_JSON` 留空并直接使用仓库里的 `android/app/google-services.json`，所以真正必须长期保存并配置的核心是：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_PROPERTIES`

## 长期维护建议

- 第一次生成的 `upload-keystore.jks` 一定要备份到安全位置
- 不要随便重新生成新的 keystore，否则以后新包无法覆盖旧包
- 不要随便改 Android 包名，否则系统会把它当成另一个应用
- 追上游时，尽量只同步业务代码，不要无意改掉你自己的签名配置

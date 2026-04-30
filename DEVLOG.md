# DEVLOG — TravelTrace 开发日志

记录开发过程中遇到的典型问题、排查过程和最终解决方案。
格式：**现象 / 根因 / 解决**。

---

## 2026-04-18 — WSL 中找不到 Linux 版 Android 工具链

**现象：**
在 Windows 上用 Android Studio 装好了 SDK（`F:\Android-studio\SDK`），
在 WSL 里挂载使用时 `flutter doctor` 报：

```
Android SDK file not found: adb
Android sdkmanager not found
```

把 Windows SDK 里的 `platform-tools/` 在 WSL 下打开，发现里面全是
`adb.exe` / `sdkmanager.bat` 等 Windows 二进制，WSL 的 Linux 环境无法执行。

**根因：**
Android Studio 只按宿主平台下载对应二进制。Windows 版 Studio 装的 SDK
内部工具链全是 Windows 可执行文件，Linux 侧无法直接使用。
进一步试过把 Linux 版 `sdkmanager` / `adb` 手动塞进共享 SDK，
但 `build-tools/` 里 `aapt` 等也缺 Linux 版本，而且 Android Studio 后续
更新 SDK 会覆盖手动放进去的 Linux 文件 —— 不可持续。

**解决：**
放弃共享 SDK，在 WSL 侧建一套独立 Linux SDK：

```bash
# 1. 独立 SDK 骨架
mkdir -p ~/Android/Sdk/cmdline-tools/latest
# 下载 Linux 版 cmdline-tools 和 platform-tools，解压到对应位置

# 2. ~/.bashrc 指向新路径
export JAVA_HOME=/home/xms/jdk/jdk-17.0.18+8
export ANDROID_SDK_ROOT=/home/xms/Android/Sdk
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:\
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH

# 3. 让 Flutter 指向新 SDK
flutter config --android-sdk ~/Android/Sdk

# 4. Linux sdkmanager 安装必要组件
sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"
```

**教训：** 跨平台共享 SDK 路径看似节省空间，实际维护成本极高；
每个操作系统维护自己的完整工具链更稳定。

---

## 2026-04-18 — Huawei HarmonyOS 3.0 上 GPS 一直返回伦敦默认值

**现象：**
App 在华为 EML-AL00（HarmonyOS 3.0，Android 10 底层）上跑起来后，
Record 页显示的当前位置固定是默认的 LatLng(51.5074, -0.1278)（伦敦）。
即使到室外、开启定位权限、`geolocator` 返回的 Position 也是这个值，
但同一台手机上的**百度地图**能正常定位。

**排查：**

```bash
adb shell dumpsys location | grep -A5 "gms"
```

输出里 `com.google.android.gms` 对应的 `monitoring location: false`。
另外 `flutter doctor` 没问题，权限也给了。

**根因：**
`geolocator` 包在 Android 上默认使用 **Google Fused Location Provider**
（`com.google.android.gms.location`）。Huawei 设备 GMS 不完整，
Fused Provider 在这类设备上无法正常接收 GPS 硬件数据 —— 所以 `getCurrentPosition`
只能返回最后一次缓存或默认坐标。

**解决：**
在 `LocationService._settings()` 里为 Android 显式启用原生 LocationManager：

```dart
if (!kIsWeb && Platform.isAndroid) {
  return AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    forceLocationManager: true,  // 绕过 GMS，用 Android 原生 API
    intervalDuration: const Duration(seconds: 2),
  );
}
```

**教训：** 在非 Google 生态（Huawei / HarmonyOS / 定制 ROM）上开发时，
优先考虑不依赖 GMS 的 API；如果第三方包默认走 GMS，要查清楚有没有开关
切到原生实现。

---

## 2026-04-18 — 自定义定位箭头在缩小地图时比街道还大

**现象：**
仿照百度地图画了一个带朝向的箭头（见 `utils/heading_marker.dart`），
在默认 zoom=15 时大小正常；但用户手指捏合缩小到城市级别时，
箭头图标像素尺寸不变，**一个箭头盖住整条街**。

**根因：**
`GoogleMap` 的 `Marker.icon` 用 `BitmapDescriptor.bytes` 生成的位图是
固定像素尺寸（96px），和地图米/像素比例无关 —— 缩小时地图内容缩小了，
而位图没缩，视觉上就越来越大。

**解决：**
在 `RecordingPage` 中监听 camera 的 zoom 变化，按 zoom 动态重建位图：

```dart
double _iconSizeForZoom(double zoom) {
  return (40.0 + (zoom - 14) * 10).clamp(28.0, 96.0);
}

// onCameraMove 里更新 _currentZoom
// onCameraIdle 里调用 _updateHeadingIconSize()：
//   如果目标 size 与当前 size 差值 < 6px 就跳过（防抖动）
//   否则调用 buildHeadingMarker(size: target) 重建，并 setState 刷新
```

关键细节：
- 只在 `onCameraIdle` 重建，不在 `onCameraMove`，避免缩放过程中一直
  重跑 PictureRecorder（开销大）
- 差值 <6px 跳过 —— 小抖动不值得触发重建
- `_regeneratingIcon` 防重入，避免连续缩放时并发调用

**教训：** 用 `BitmapDescriptor.bytes` 自定义 marker 的代价就是"自己扛
缩放适配"。Flutter Google Maps 目前没有原生的"跟随 zoom 自动缩放 marker"
API，必须手动监听并重建。

---

## 2026-04-18 — 开阔广场轨迹瞬移 + self 箭头不跟随

**现象：**
在华为 EML-AL00 真机上：
1. 站在没遮挡的广场，record 起来后 polyline 会隔几秒"瞬移"几十米到
   几百米，再跳回来。Google 地图 / 百度地图同样位置没这种抖动。
2. 进 Record 页面不按 Start 录制时，蓝色自定义箭头**完全不动**；
   要按 Start 之后箭头才开始跟着走。

**根因：**
1. 上一条日志里把 `forceLocationManager: true` 打开之后，geolocator 走的是
   原生 Android `LocationManager`。`LocationManager` 同时开启 `GPS`
   和 `NETWORK` 两个 provider，**不做 fusion**。NETWORK provider 用的是
   基站/WiFi 三角定位，精度 100–1000 m；两个 provider 的 fix 交替进流，
   NETWORK 那批就是瞬移点。华为没完整 GMS，没有 Fused Location Provider
   给我们做融合 —— 这个坑是 GMS 缺失的二次后果。
2. `RecordingPage._initLocation()` 只在 initState 里 `getCurrentPosition`
   拿一次当前位置；真正订阅 `positionStream` 的代码放在 `_startRecording`
   里 —— 不录制 = 没订阅 = 箭头不动。直觉上用户打开这页就应该看到自己
   实时位置，不应该让"录制"和"定位显示"绑死。

**解决：**
1. `LocationService._onPosition()` 加两道门：
   ```dart
   // gate 1: accuracy
   if (position.accuracy > 30.0) return;
   // gate 2: implied speed against the last accepted point
   final dtSec = now.difference(prevAt).inMilliseconds / 1000.0;
   final metres = Geolocator.distanceBetween(prev.lat, prev.lng, p.lat, p.lng);
   if (metres / dtSec > 56.0) return;  // ~200 km/h
   ```
   两道门都是设备无关的通用清洗：Pixel 有 FLP 融合基本不会被误杀，
   Huawei 靠它过滤 NETWORK 烂 fix。
2. 拆 `startLiveUpdates()` / `startTracking()` 两层语义：
   - `startLiveUpdates()`：开启 position 流，过滤后 emit 到
     `positionController`，幂等（重复调用不会重复订阅）
   - `startTracking()`：只把 `_isTracking=true`，累积 TrackPoint
   - `stopTracking()`：只把 `_isTracking=false`，**不取消订阅**
3. `RecordingPage.initState` 直接 `startLiveUpdates()` 并订阅
   positionStream 更新自定义箭头位置；`_startRecording` 不再单独订阅
   positionStream，避免两路订阅重复。`dispose` 时才 stopLiveUpdates。

**教训：**
- `forceLocationManager` 解决 "GMS 没有" 的问题，但把 "没有 fusion"
  的副作用推给了应用层 —— 在应用层补回精度/速度过滤是必要的。
- 功能应该按用户心智模型设计边界（"这页一直显示我的位置"），
  不要让实现细节（"只有按 Start 才订阅"）泄漏到 UX。

---

## 2026-04-18 — 同一地点拍多张照片只能看到一张

**现象：**
在同一个地方连拍了 3 张照片，进 Trip Detail 页，地图上只显示一个
蓝色照片 marker。点击它只能打开其中一张预览，另外两张像"消失"了
（但底部 summary bar 的 Photos 计数是 3）。

**根因：**
之前的 `_buildMarkers()` 为每张 `PhotoMarker` 都 `markers.add` 一个
独立 Marker，`markerId` 用 `photo.id`。三张照片的经纬度几乎完全一致，
Google Maps 把它们堆在同一像素点：视觉上就是一个 marker，点击只能
命中最上层那一个。数据没丢，只是 UI 没表达多张。

**解决：**
在 `trip_detail_page.dart` 加贪心聚合 `_clusterPhotos()`：
- 半径阈值 10 m（5 m 容易把同一地点的照片因 GPS 噪声分到不同组）
- 用 `Geolocator.distanceBetween` 和**每组第一张**（anchor）比距离，
  命中则入组，否则新开组
- 每组渲染一个 marker，`infoWindow` 显 `"N photos"`（N>1 时）
- 点击：单张照片直接 `_PhotoPreviewSheet`；多张弹 `_PhotoClusterSheet`，
  内部横向滚动缩略图，点缩略图 pop 掉 sheet 再进全屏预览

**教训：** Google Maps 的 marker 没有自动聚合机制（不像 Leaflet /
Mapbox 有 MarkerClusterer）。任何可能坐标重合的 marker 都要在业务层
自己聚合，不然就是"数据在、UI 不在"的隐形 bug。

---

## 2026-04-18 — Home 页统计永远显示 0

**现象：**
录制了若干 journey 后，Trip History 页和 Record 页都正常更新，唯独
Home 页顶部三张卡片 Journeys / Total km / Photos 一直显示 `0`，
底下 "Recent Journeys" 也永远是空状态。

**根因：**
`home_page.dart` 从 Phase 2 以来就是 `StatelessWidget`，三张卡片里的
`value` 参数硬编码字符串 `'0'`，`_EmptyJourneysState` 也是静态组件。
Phase 5 接入 SQLite 时只改了 History / Detail / Record 三页，Home 页
没纳入 DB 订阅网络 —— "看起来像真数据的空壳"最容易被遗漏。

**解决：**
1. `DatabaseService.loadStats()`：一次 SQL 聚合出 `tripCount`、`photoCount`，
   再扫 `track_points`（按 `trip_id, timestamp` 排序）按 trip 分段累加
   `Geolocator.distanceBetween` 得到 `totalMeters`。每次调用开销约等于
   一条完整 Trip Detail 查询，Phase 5 量级完全可接受。
2. `HomePage` 改 `StatefulWidget`：`initState` 里 `_load()` + `addListener`
   到 `DatabaseService.instance.tripsRevision`，save/delete 自动刷新。
3. "Recent Journeys" 取 `loadTrips().take(3)`，超过 3 条显示 "See all"
   跳 History tab。

**教训：** 占位 UI（硬编码 `'0'` / 静态空状态）在搭骨架阶段必要，
但接数据的那一次提交必须**一次性把所有消费该数据的页面都接上**。
留一个"看起来能用"的页面最后会被当成 bug 反馈回来。

---

## 2026-04-29 — 隔天再开 app 照片全打不开（marker 在但图空）

**现象：**
真机录一条 trip 拍 1-2 张照，当场进 History → Trip Detail 一切正常。
**关闭 app 过一晚再打开**，进同一条 trip：地图 polyline / start-end pin /
photo marker 位置全部还在，但点 marker 弹出的预览 sheet **完全空白**，
回放游标进入照片时间窗时浮现的缩略卡也是空白。`flutter analyze` 没报错，
也没崩溃日志，UI 静默失败。

**根因：**
`image_picker` 默认把照片落到 app 的 **cache / temporary** 目录
（Android 上类似 `/data/data/com.example.app/cache/image_picker_xxx.jpg`）。
系统会在 app 关闭后或周期维护时清理这块目录。`CameraService.takePhoto()`
当时直接 `return image?.path`，把临时路径作为绝对路径写进 SQLite。
照片文件被系统清掉之后，DB 里的字符串还在，`File(path).exists()` 变 false，
但 `Image.file(File(path))` 的三个调用点（`trip_detail_page.dart:752 / 893
/ 1264`）**都没传 errorBuilder**，Flutter 默认行为是渲染零尺寸 + 把异常吞到
`FlutterError.onError`，不会冒到 console，更不会影响布局 —— 所以肉眼看是
"空白"，调试时极易被当成 layout 问题去查。

**解决：**
1. **拍完立即 copy 到永久目录**：`CameraService` 加 `_persist(XFile)` 把
   image_picker 给的临时文件 `File.copy()` 到
   `getApplicationDocumentsDirectory()/photos/{uuid}.jpg`。`takePhoto` 和
   `pickFromGallery` 都走这条路径，对外签名（`Future<String?>`）不变。
   pubspec 已有 `path_provider` / `path` / `uuid`，无需新增依赖。
2. **UI 兜底**：`trip_detail_page.dart` 三处 `Image.file` / `Image.network`
   全部加 `errorBuilder`，文件末尾抽出 `_missingPhotoPlaceholder(context,
   {required bool large})` 渲染 `surfaceContainerHighest` 底色 +
   `Icons.broken_image_outlined` + "Photo unavailable" 文案（large 模式才
   显示文案）。这样旧 trip 已经丢掉的照片不再静默空白。
3. **不做迁移**：已经丢的图找不回来，没必要写脚本清死路径 —— 万一某些
   cache 还没被清的死路径用户后续重启又能复活，留着反而是好事。Demo
   场景下用户可以删旧 trip 重录。

**教训：** `image_picker` 返回的 path **永远不要**直接写库。Android 的
cache 目录寿命由系统决定，跟 app 生命周期无关。任何"用户产出 + 长期持有"
的二进制资产都必须在产生当下就落到 `getApplicationDocumentsDirectory()`
或 `getApplicationSupportDirectory()`。同时所有 `Image.file` 调用都该有
errorBuilder —— 默认静默失败这一点对调试和 UX 都极不友好。

---

# VidPress

VidPress 是一款 SwiftUI/AppKit 原生 macOS 本地视频压缩 app。视频文件只在本机处理，不需要上传到网站，也不再使用 Electron、WebView、React 或 Vite 作为界面运行时。

## 功能

- 原生 SwiftUI/AppKit 界面，支持拖拽、文件选择、队列、进度、取消任务、访达定位。
- Release 版内置 FFmpeg 和 FFprobe，视频压缩默认不依赖外部网站或 Homebrew。
- 支持常见输入格式：MP4、MOV、M4V、MKV、WebM、AVI、WMV、FLV、MPEG、3GP、TS、MTS、M2TS。
- 支持导出格式：MP4、MOV、MKV、WebM、AVI。
- 傻瓜模式：视频无损、高质量、均衡、小体积、社交平台。
- 专业模式：视频编码、CRF、码率、编码速度、分辨率、帧率、音频编码、音频码率、移除音频。
- 专业参数会按导出格式自动过滤兼容编码，避免常见 FFmpeg 容器/编码组合错误。
- 会记住上次使用的导出目录、模式、格式和专业参数。
- FFmpeg/FFprobe 错误会转换为更容易理解的提示，同时保留关键原始日志。

## 环境

- macOS 13 或更新版本。
- Swift Command Line Tools 即可构建；安装完整 Xcode 后也可以继续扩展成标准 Xcode 工程。
- `package.json` 只保留 FFmpeg/FFprobe 二进制下载用途，不再包含 Web UI 依赖。

## 准备 FFmpeg

```bash
npm install
```

如果安装 `ffmpeg-static` 时 GitHub 下载较慢，可以使用镜像：

```bash
npm run bootstrap:cn
```

## 本地运行

VidPress 会优先使用 `.app` 内置 FFmpeg/FFprobe，其次查找 `VIDPRESS_FFMPEG_PATH`、`VIDPRESS_FFPROBE_PATH`、`FFMPEG_PATH`、`FFPROBE_PATH`，最后查找 Homebrew 或系统路径。

```bash
swift run VidPressNative
```

## 构建发行包

```bash
npm run dist
```

产物会输出到 `release/`：

- `release/VidPress.app`
- `release/VidPress-native-mac-arm64.zip`

打包脚本会写入 AppKit 启动元数据，把 `node_modules` 中的 FFmpeg/FFprobe 复制进 `.app/Contents/Resources/`，并做本地 ad-hoc 签名。ad-hoc 签名适合本机开发和测试；公开分发仍建议使用 Apple Developer Program 的 Developer ID 签名与 notarization。

## 说明

“无损压缩”当前采用视觉无损倾向的高质量重编码，体积不一定比原视频更小；不同源视频、编码器和容器格式会影响最终结果。

Release 包内的 FFmpeg 来自 `ffmpeg-static`，遵循其上游 GPL-3.0-or-later 许可；FFprobe 来自 `ffprobe-static`。

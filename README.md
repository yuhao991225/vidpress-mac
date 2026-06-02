# VidPress

VidPress 是一款 macOS 本地视频压缩桌面 app。视频文件只在本机处理，不需要上传到网站。

## 功能

- Release 版内置 FFmpeg 和 FFprobe，视频压缩默认不依赖外部网站或 Homebrew。
- 支持常见输入格式：MP4、MOV、M4V、MKV、WebM、AVI、WMV、FLV、MPEG、3GP、TS、MTS、M2TS。
- 支持导出格式：MP4、MOV、MKV、WebM、AVI。
- 傻瓜模式：视频无损、高质量、均衡、小体积、社交平台。
- 专业模式：视频编码、CRF、码率、编码速度、分辨率、帧率、音频编码、音频码率、移除音频。
- 批量队列、进度显示、取消任务、导出后在访达中显示。

## 本地运行

VidPress 会优先使用内置 FFmpeg/FFprobe，随后才会查找 `FFMPEG_PATH`、`FFPROBE_PATH` 或系统路径里的 `ffmpeg` 和 `ffprobe`。

```bash
npm install
npm run dev
```

如果安装 `ffmpeg-static` 时 GitHub 下载较慢，可以使用镜像：

```bash
npm run bootstrap:cn
npm run dev
```

## 构建

```bash
npm run build
npm run dist
```

默认构建 macOS arm64 zip，产物会输出到 `release/`，解压后得到 `VidPress.app`。脚本会在运行前执行 `npm run prepare-electron`，通过 Electron 镜像补齐桌面运行时。

## 说明

“视频无损”会对画面做无损重编码，体积不一定比原视频更小；不同源视频、编码器和容器格式会影响最终结果。

Release 包内的 FFmpeg 来自 `ffmpeg-static`，遵循其上游 GPL-3.0-or-later 许可；FFprobe 来自 `ffprobe-static`。

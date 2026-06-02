import { app, BrowserWindow, dialog, ipcMain, shell, WebContents } from 'electron';
import { ChildProcessWithoutNullStreams, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  AudioCodec,
  CompressionRequest,
  CompressionResult,
  EngineState,
  JobProgress,
  MediaFile,
  OutputFormat,
  ProfessionalSettings,
  SimplePreset,
  VideoCodec
} from './shared';

const SUPPORTED_INPUT_EXTENSIONS = [
  'mp4',
  'mov',
  'm4v',
  'mkv',
  'webm',
  'avi',
  'wmv',
  'flv',
  'mpeg',
  'mpg',
  '3gp',
  'ts',
  'mts',
  'm2ts'
];

const runningJobs = new Map<string, ChildProcessWithoutNullStreams>();
const cancelledJobs = new Set<string>();

let mainWindow: BrowserWindow | null = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1220,
    height: 780,
    minWidth: 960,
    minHeight: 680,
    title: 'VidPress',
    backgroundColor: '#f7f7f4',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  const devServerUrl = process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    mainWindow.loadURL(devServerUrl);
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }
}

app.whenReady().then(() => {
  registerIpc();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  for (const child of runningJobs.values()) {
    child.kill('SIGTERM');
  }

  if (process.platform !== 'darwin') {
    app.quit();
  }
});

function registerIpc() {
  ipcMain.handle('app:get-engine-state', async (): Promise<EngineState> => {
    const ffmpegPath = await resolveBinary('ffmpeg');
    const ffprobePath = await resolveBinary('ffprobe');
    const defaultOutputDir = await ensureDefaultOutputDir();

    return {
      ffmpegPath,
      ffprobePath,
      ffmpegReady: Boolean(ffmpegPath),
      ffprobeReady: Boolean(ffprobePath),
      defaultOutputDir,
      supportedInputExtensions: SUPPORTED_INPUT_EXTENSIONS
    };
  });

  ipcMain.handle('dialog:select-videos', async (): Promise<MediaFile[]> => {
    const result = await dialog.showOpenDialog({
      title: '选择视频',
      properties: ['openFile', 'multiSelections'],
      filters: [
        {
          name: 'Videos',
          extensions: SUPPORTED_INPUT_EXTENSIONS
        }
      ]
    });

    if (result.canceled) {
      return [];
    }

    return inspectFiles(result.filePaths);
  });

  ipcMain.handle('dialog:select-output-folder', async (): Promise<string | undefined> => {
    const result = await dialog.showOpenDialog({
      title: '选择导出文件夹',
      properties: ['openDirectory', 'createDirectory']
    });

    return result.canceled ? undefined : result.filePaths[0];
  });

  ipcMain.handle('media:inspect', async (_event, filePaths: string[]): Promise<MediaFile[]> => {
    return inspectFiles(filePaths);
  });

  ipcMain.handle('compress:start', async (event, request: CompressionRequest): Promise<CompressionResult> => {
    return startCompression(event.sender, request);
  });

  ipcMain.handle('compress:cancel', async (_event, jobId: string): Promise<boolean> => {
    cancelledJobs.add(jobId);
    const child = runningJobs.get(jobId);
    if (!child) {
      return false;
    }

    child.kill('SIGTERM');
    return true;
  });

  ipcMain.handle('shell:reveal-file', async (_event, filePath: string): Promise<void> => {
    shell.showItemInFolder(filePath);
  });
}

async function ensureDefaultOutputDir() {
  const outputDir = path.join(os.homedir(), 'Movies', 'VidPress Exports');
  await fs.promises.mkdir(outputDir, { recursive: true });
  return outputDir;
}

async function resolveBinary(binaryName: 'ffmpeg' | 'ffprobe') {
  const envPath = binaryName === 'ffmpeg' ? process.env.FFMPEG_PATH : process.env.FFPROBE_PATH;
  const candidates = [
    envPath,
    binaryName,
    `/opt/homebrew/bin/${binaryName}`,
    `/usr/local/bin/${binaryName}`,
    `/usr/bin/${binaryName}`
  ].filter(Boolean) as string[];

  for (const candidate of candidates) {
    if (await canRun(candidate, ['-version'])) {
      return candidate;
    }
  }

  return undefined;
}

function canRun(command: string, args: string[]) {
  return new Promise<boolean>((resolve) => {
    const child = spawn(command, args);
    child.once('error', () => resolve(false));
    child.once('close', (code) => resolve(code === 0));
  });
}

async function inspectFiles(filePaths: string[]) {
  const uniquePaths = [...new Set(filePaths)].filter(isSupportedVideoFile);
  const files = await Promise.all(uniquePaths.map(inspectFile));
  return files.filter(Boolean) as MediaFile[];
}

function isSupportedVideoFile(filePath: string) {
  const ext = path.extname(filePath).replace('.', '').toLowerCase();
  return SUPPORTED_INPUT_EXTENSIONS.includes(ext);
}

async function inspectFile(filePath: string): Promise<MediaFile | undefined> {
  try {
    const stats = await fs.promises.stat(filePath);
    const metadata = await probeMedia(filePath);

    return {
      id: hashFileId(filePath, stats.size, stats.mtimeMs),
      path: filePath,
      name: path.basename(filePath),
      size: stats.size,
      ...metadata
    };
  } catch {
    return undefined;
  }
}

function hashFileId(filePath: string, size: number, mtimeMs: number) {
  return crypto.createHash('sha1').update(`${filePath}:${size}:${mtimeMs}`).digest('hex');
}

async function probeMedia(filePath: string) {
  const ffprobePath = await resolveBinary('ffprobe');
  if (!ffprobePath) {
    return {};
  }

  const result = await captureProcess(ffprobePath, [
    '-v',
    'error',
    '-print_format',
    'json',
    '-show_format',
    '-show_streams',
    filePath
  ]);

  if (result.code !== 0 || !result.stdout.trim()) {
    return {};
  }

  try {
    const data = JSON.parse(result.stdout) as {
      format?: { duration?: string; format_long_name?: string; format_name?: string };
      streams?: Array<{
        codec_type?: string;
        codec_name?: string;
        width?: number;
        height?: number;
        duration?: string;
      }>;
    };
    const video = data.streams?.find((stream) => stream.codec_type === 'video');
    const audio = data.streams?.find((stream) => stream.codec_type === 'audio');
    const duration = Number(data.format?.duration ?? video?.duration ?? 0);

    return {
      duration: Number.isFinite(duration) && duration > 0 ? duration : undefined,
      width: video?.width,
      height: video?.height,
      videoCodec: video?.codec_name,
      audioCodec: audio?.codec_name,
      format: data.format?.format_long_name ?? data.format?.format_name
    };
  } catch {
    return {};
  }
}

function captureProcess(command: string, args: string[]) {
  return new Promise<{ code: number | null; stdout: string; stderr: string }>((resolve) => {
    const child = spawn(command, args);
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', (error) => {
      stderr += error.message;
      resolve({ code: 1, stdout, stderr });
    });
    child.on('close', (code) => {
      resolve({ code, stdout, stderr });
    });
  });
}

async function startCompression(webContents: WebContents, request: CompressionRequest): Promise<CompressionResult> {
  const ffmpegPath = await resolveBinary('ffmpeg');
  if (!ffmpegPath) {
    throw new Error('没有找到 ffmpeg。请先通过 Homebrew 安装 ffmpeg，或设置 FFMPEG_PATH。');
  }

  await fs.promises.mkdir(request.outputDir, { recursive: true });

  const media = await probeMedia(request.inputPath);
  const outputPath = await createOutputPath(request);
  const ffmpegArgs = buildFfmpegArgs(request, outputPath);
  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    const child = spawn(ffmpegPath, ffmpegArgs);
    runningJobs.set(request.jobId, child);

    let stderrBuffer = '';

    child.stderr.on('data', (chunk) => {
      stderrBuffer += chunk.toString();
      const progress = parseProgress(stderrBuffer, request.jobId, media.duration);
      if (progress) {
        webContents.send('job:progress', progress);
      }

      if (stderrBuffer.length > 8000) {
        stderrBuffer = stderrBuffer.slice(-4000);
      }
    });

    child.on('error', (error) => {
      runningJobs.delete(request.jobId);
      cancelledJobs.delete(request.jobId);
      reject(error);
    });

    child.on('close', async (code) => {
      runningJobs.delete(request.jobId);
      const elapsedMs = Date.now() - startedAt;

      if (cancelledJobs.has(request.jobId)) {
        cancelledJobs.delete(request.jobId);
        await removePartialOutput(outputPath);
        resolve({
          jobId: request.jobId,
          status: 'cancelled',
          elapsedMs
        });
        return;
      }

      if (code !== 0) {
        await removePartialOutput(outputPath);
        reject(new Error(tailFfmpegError(stderrBuffer)));
        return;
      }

      const outputStats = await fs.promises.stat(outputPath);
      resolve({
        jobId: request.jobId,
        status: 'done',
        outputPath,
        outputSize: outputStats.size,
        elapsedMs
      });
    });
  });
}

async function createOutputPath(request: CompressionRequest) {
  const inputBase = path.basename(request.inputPath, path.extname(request.inputPath));
  const safeBase = inputBase.replace(/[/:*?"<>|]/g, '-').trim() || 'video';
  const suffix = request.mode === 'simple' ? request.preset : 'pro';
  const ext = request.outputFormat;
  let candidate = path.join(request.outputDir, `${safeBase}-${suffix}.${ext}`);
  let index = 2;

  while (fs.existsSync(candidate)) {
    candidate = path.join(request.outputDir, `${safeBase}-${suffix}-${index}.${ext}`);
    index += 1;
  }

  return candidate;
}

function buildFfmpegArgs(request: CompressionRequest, outputPath: string) {
  const args = ['-hide_banner', '-y', '-i', request.inputPath, '-map', '0:v:0', '-map', '0:a?'];

  if (request.mode === 'professional') {
    applyProfessionalSettings(args, request.outputFormat, request.professional);
  } else {
    applySimplePreset(args, request.outputFormat, request.preset);
  }

  applyContainerFlags(args, request.outputFormat);
  args.push(outputPath);
  return args;
}

function applySimplePreset(args: string[], format: OutputFormat, preset: SimplePreset) {
  if (preset === 'lossless') {
    if (format === 'webm') {
      args.push('-c:v', 'libvpx-vp9', '-lossless', '1', '-deadline', 'good', '-cpu-used', '3', '-c:a', 'libopus', '-b:a', '192k');
      return;
    }

    if (format === 'avi') {
      args.push('-c:v', 'ffv1', '-level', '3', '-c:a', 'copy');
      return;
    }

    args.push('-c:v', 'libx264', '-preset', 'slow', '-crf', '0', '-c:a', 'copy');
    if (format === 'mp4' || format === 'mov') {
      args.push('-pix_fmt', 'yuv420p');
    }
    return;
  }

  const simpleMatrix: Record<Exclude<SimplePreset, 'lossless'>, { crf: number; preset: string; maxSize?: [number, number]; audio: string }> = {
    high: { crf: 18, preset: 'slow', audio: '192k' },
    balanced: { crf: 23, preset: 'medium', audio: '160k' },
    small: { crf: 30, preset: 'slow', maxSize: [1280, 720], audio: '96k' },
    social: { crf: 24, preset: 'fast', maxSize: [1920, 1080], audio: '128k' }
  };

  const selected = simpleMatrix[preset];

  if (selected.maxSize) {
    args.push('-vf', scaleFilter(selected.maxSize[0], selected.maxSize[1]));
  }

  if (preset === 'social') {
    args.push('-r', '30');
  }

  if (format === 'webm') {
    args.push('-c:v', 'libvpx-vp9', '-crf', String(selected.crf + 6), '-b:v', '0', '-deadline', 'good', '-cpu-used', '4');
    args.push('-c:a', 'libopus', '-b:a', selected.audio);
    return;
  }

  if (format === 'avi') {
    const quality = preset === 'high' ? '2' : preset === 'balanced' ? '4' : '7';
    args.push('-c:v', 'mpeg4', '-q:v', quality, '-c:a', 'libmp3lame', '-b:a', selected.audio);
    return;
  }

  args.push('-c:v', 'libx264', '-preset', selected.preset, '-crf', String(selected.crf), '-pix_fmt', 'yuv420p');
  args.push('-c:a', audioCodecForContainer(format, 'aac'), '-b:a', selected.audio);
}

function applyProfessionalSettings(args: string[], format: OutputFormat, settings: ProfessionalSettings) {
  const requestedVideo = normalizeVideoCodec(format, settings.videoCodec);
  const requestedAudio = normalizeAudioCodec(format, settings.audioCodec);
  const hasVideoFilters = settings.videoCodec !== 'copy' && settings.resolution !== 'source';

  if (hasVideoFilters) {
    const dimensions = dimensionsForResolution(settings);
    if (dimensions) {
      args.push('-vf', scaleFilter(dimensions[0], dimensions[1]));
    }
  }

  if (settings.fps.trim() && requestedVideo !== 'copy') {
    args.push('-r', settings.fps.trim());
  }

  applyVideoCodecArgs(args, requestedVideo, settings);

  if (settings.removeAudio) {
    args.push('-an');
    return;
  }

  if (requestedAudio === 'copy') {
    args.push('-c:a', 'copy');
  } else {
    args.push('-c:a', audioCodecForContainer(format, requestedAudio), '-b:a', settings.audioBitrate || '128k');
  }
}

function applyVideoCodecArgs(args: string[], codec: VideoCodec, settings: ProfessionalSettings) {
  if (codec === 'copy') {
    args.push('-c:v', 'copy');
    return;
  }

  if (codec === 'h264') {
    args.push('-c:v', 'libx264', '-preset', settings.encodingPreset, '-pix_fmt', 'yuv420p');
    applyRateControl(args, settings, false);
    return;
  }

  if (codec === 'h265') {
    args.push('-c:v', 'libx265', '-preset', settings.encodingPreset, '-pix_fmt', 'yuv420p');
    applyRateControl(args, settings, false);
    return;
  }

  if (codec === 'vp9') {
    args.push('-c:v', 'libvpx-vp9', '-deadline', 'good', '-cpu-used', '4');
    applyRateControl(args, settings, true);
    return;
  }

  if (codec === 'av1') {
    args.push('-c:v', 'libaom-av1', '-cpu-used', '5');
    applyRateControl(args, settings, false);
    return;
  }

  args.push('-c:v', 'mpeg4', '-q:v', qualityFromCrf(settings.crf));
}

function applyRateControl(args: string[], settings: ProfessionalSettings, zeroBitrateForCrf: boolean) {
  const bitrate = settings.videoBitrate.trim();
  if (bitrate) {
    args.push('-b:v', bitrate);
    return;
  }

  args.push('-crf', String(settings.crf));
  if (zeroBitrateForCrf) {
    args.push('-b:v', '0');
  }
}

function normalizeVideoCodec(format: OutputFormat, codec: VideoCodec): VideoCodec {
  if (format === 'webm' && codec !== 'vp9' && codec !== 'av1' && codec !== 'copy') {
    return 'vp9';
  }

  if (format === 'avi' && (codec === 'vp9' || codec === 'av1' || codec === 'h265')) {
    return 'mpeg4';
  }

  return codec;
}

function normalizeAudioCodec(format: OutputFormat, codec: AudioCodec): AudioCodec {
  if (codec === 'copy') {
    return codec;
  }

  if (format === 'webm') {
    return 'opus';
  }

  if (format === 'avi') {
    return 'mp3';
  }

  if (format === 'mp4' || format === 'mov') {
    return codec === 'opus' ? 'aac' : codec;
  }

  return codec;
}

function audioCodecForContainer(format: OutputFormat, codec: Exclude<AudioCodec, 'copy'>) {
  const normalized = normalizeAudioCodec(format, codec);

  if (normalized === 'opus') {
    return 'libopus';
  }

  if (normalized === 'mp3') {
    return 'libmp3lame';
  }

  return 'aac';
}

function dimensionsForResolution(settings: ProfessionalSettings): [number, number] | undefined {
  const presets: Record<string, [number, number]> = {
    '2160p': [3840, 2160],
    '1080p': [1920, 1080],
    '720p': [1280, 720],
    '480p': [854, 480]
  };

  if (settings.resolution === 'custom') {
    return [
      clampInteger(settings.customWidth, 160, 7680),
      clampInteger(settings.customHeight, 90, 4320)
    ];
  }

  return presets[settings.resolution];
}

function scaleFilter(width: number, height: number) {
  return `scale=w='min(${width},iw)':h='min(${height},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2`;
}

function clampInteger(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) {
    return min;
  }

  return Math.min(max, Math.max(min, Math.round(value)));
}

function qualityFromCrf(crf: number) {
  const normalized = clampInteger(crf, 0, 40);
  if (normalized <= 18) return '2';
  if (normalized <= 24) return '4';
  if (normalized <= 30) return '6';
  return '8';
}

function applyContainerFlags(args: string[], format: OutputFormat) {
  if (format === 'mp4' || format === 'mov') {
    args.push('-movflags', '+faststart');
  }
}

function parseProgress(stderr: string, jobId: string, duration?: number): JobProgress | undefined {
  const timeMatches = [...stderr.matchAll(/time=(\d+):(\d+):(\d+(?:\.\d+)?)/g)];
  const lastTime = timeMatches.at(-1);
  if (!lastTime) {
    return undefined;
  }

  const hours = Number(lastTime[1]);
  const minutes = Number(lastTime[2]);
  const seconds = Number(lastTime[3]);
  const elapsedSeconds = hours * 3600 + minutes * 60 + seconds;

  const speed = stderr.match(/speed=\s*([^\s]+)/)?.[1];
  const fps = stderr.match(/fps=\s*([^\s]+)/)?.[1];
  const size = stderr.match(/size=\s*([^\s]+)/)?.[1];
  const percent = duration && duration > 0 ? Math.min(100, Math.round((elapsedSeconds / duration) * 100)) : 0;

  return {
    jobId,
    percent,
    elapsedSeconds,
    speed,
    fps,
    size
  };
}

function tailFfmpegError(stderr: string) {
  const lines = stderr
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.slice(-8).join('\n') || 'FFmpeg 压缩失败。';
}

async function removePartialOutput(outputPath: string) {
  try {
    await fs.promises.unlink(outputPath);
  } catch {
    // Partial files are best-effort cleanup only.
  }
}

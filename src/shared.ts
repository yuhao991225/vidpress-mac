export type OutputFormat = 'mp4' | 'mov' | 'mkv' | 'webm' | 'avi';

export type AppMode = 'simple' | 'professional';

export type SimplePreset = 'lossless' | 'high' | 'balanced' | 'small' | 'social';

export type VideoCodec = 'h264' | 'h265' | 'vp9' | 'av1' | 'mpeg4' | 'copy';

export type AudioCodec = 'aac' | 'opus' | 'mp3' | 'copy';

export type ResolutionPreset = 'source' | '2160p' | '1080p' | '720p' | '480p' | 'custom';

export interface MediaFile {
  id: string;
  path: string;
  name: string;
  size: number;
  duration?: number;
  width?: number;
  height?: number;
  videoCodec?: string;
  audioCodec?: string;
  format?: string;
}

export interface ProfessionalSettings {
  videoCodec: VideoCodec;
  audioCodec: AudioCodec;
  crf: number;
  videoBitrate: string;
  encodingPreset: 'ultrafast' | 'superfast' | 'veryfast' | 'faster' | 'fast' | 'medium' | 'slow' | 'slower' | 'veryslow';
  resolution: ResolutionPreset;
  customWidth: number;
  customHeight: number;
  fps: string;
  audioBitrate: string;
  removeAudio: boolean;
}

export interface CompressionRequest {
  jobId: string;
  inputPath: string;
  outputDir: string;
  outputFormat: OutputFormat;
  mode: AppMode;
  preset: SimplePreset;
  professional: ProfessionalSettings;
}

export interface JobProgress {
  jobId: string;
  percent: number;
  elapsedSeconds: number;
  speed?: string;
  fps?: string;
  size?: string;
}

export interface CompressionResult {
  jobId: string;
  status: 'done' | 'cancelled';
  outputPath?: string;
  outputSize?: number;
  elapsedMs?: number;
}

export interface EngineState {
  ffmpegPath?: string;
  ffprobePath?: string;
  ffmpegReady: boolean;
  ffprobeReady: boolean;
  defaultOutputDir: string;
  supportedInputExtensions: string[];
}

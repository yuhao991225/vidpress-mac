import {
  CompressionRequest,
  CompressionResult,
  EngineState,
  JobProgress,
  MediaFile
} from './shared';

declare module '*.css';

declare global {
  interface Window {
    vidpress: {
      getEngineState: () => Promise<EngineState>;
      selectVideos: () => Promise<MediaFile[]>;
      selectOutputFolder: () => Promise<string | undefined>;
      inspectFiles: (filePaths: string[]) => Promise<MediaFile[]>;
      startCompression: (request: CompressionRequest) => Promise<CompressionResult>;
      cancelCompression: (jobId: string) => Promise<boolean>;
      revealFile: (filePath: string) => Promise<void>;
      onProgress: (callback: (progress: JobProgress) => void) => () => void;
    };
  }
}

export {};

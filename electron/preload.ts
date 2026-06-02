import { contextBridge, ipcRenderer } from 'electron';
import {
  CompressionRequest,
  CompressionResult,
  EngineState,
  JobProgress,
  MediaFile
} from './shared';

const api = {
  getEngineState: (): Promise<EngineState> => ipcRenderer.invoke('app:get-engine-state'),
  selectVideos: (): Promise<MediaFile[]> => ipcRenderer.invoke('dialog:select-videos'),
  selectOutputFolder: (): Promise<string | undefined> => ipcRenderer.invoke('dialog:select-output-folder'),
  inspectFiles: (filePaths: string[]): Promise<MediaFile[]> => ipcRenderer.invoke('media:inspect', filePaths),
  startCompression: (request: CompressionRequest): Promise<CompressionResult> => ipcRenderer.invoke('compress:start', request),
  cancelCompression: (jobId: string): Promise<boolean> => ipcRenderer.invoke('compress:cancel', jobId),
  revealFile: (filePath: string): Promise<void> => ipcRenderer.invoke('shell:reveal-file', filePath),
  onProgress: (callback: (progress: JobProgress) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, progress: JobProgress) => callback(progress);
    ipcRenderer.on('job:progress', listener);
    return () => ipcRenderer.removeListener('job:progress', listener);
  }
};

contextBridge.exposeInMainWorld('vidpress', api);

import {
  CheckCircle2,
  ChevronDown,
  CircleStop,
  Clapperboard,
  Download,
  FileVideo,
  FolderOpen,
  Gauge,
  Loader2,
  Play,
  Plus,
  RotateCcw,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Trash2,
  X
} from 'lucide-react';
import { DragEvent, ReactNode, useEffect, useMemo, useState } from 'react';
import {
  AppMode,
  CompressionRequest,
  EngineState,
  JobProgress,
  MediaFile,
  OutputFormat,
  ProfessionalSettings,
  SimplePreset
} from './shared';

type JobStatus = 'idle' | 'queued' | 'running' | 'done' | 'error' | 'cancelled';

interface JobState {
  jobId?: string;
  status: JobStatus;
  progress: number;
  outputPath?: string;
  outputSize?: number;
  error?: string;
  speed?: string;
  fps?: string;
}

const simplePresets: Array<{ value: SimplePreset; label: string; detail: string }> = [
  { value: 'lossless', label: '视频无损', detail: '画面无损重编码' },
  { value: 'high', label: '高质量', detail: '更细腻，体积适中' },
  { value: 'balanced', label: '均衡', detail: '日常最稳选择' },
  { value: 'small', label: '小体积', detail: '优先节省空间' },
  { value: 'social', label: '社交平台', detail: '1080p / 30fps' }
];

const outputFormats: OutputFormat[] = ['mp4', 'mov', 'mkv', 'webm', 'avi'];

const defaultProfessional: ProfessionalSettings = {
  videoCodec: 'h264',
  audioCodec: 'aac',
  crf: 23,
  videoBitrate: '',
  encodingPreset: 'medium',
  resolution: 'source',
  customWidth: 1920,
  customHeight: 1080,
  fps: '',
  audioBitrate: '128k',
  removeAudio: false
};

function App() {
  const [engine, setEngine] = useState<EngineState | null>(null);
  const [files, setFiles] = useState<MediaFile[]>([]);
  const [jobs, setJobs] = useState<Record<string, JobState>>({});
  const [mode, setMode] = useState<AppMode>('simple');
  const [preset, setPreset] = useState<SimplePreset>('balanced');
  const [outputFormat, setOutputFormat] = useState<OutputFormat>('mp4');
  const [outputDir, setOutputDir] = useState('');
  const [professional, setProfessional] = useState<ProfessionalSettings>(defaultProfessional);
  const [isRunning, setIsRunning] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const [activeJobId, setActiveJobId] = useState<string | null>(null);

  useEffect(() => {
    window.vidpress.getEngineState().then((state) => {
      setEngine(state);
      setOutputDir(state.defaultOutputDir);
    });

    return window.vidpress.onProgress((progress) => {
      setJobs((current) => applyProgress(current, progress));
    });
  }, []);

  const totals = useMemo(() => {
    const inputSize = files.reduce((total, file) => total + file.size, 0);
    const outputSize = files.reduce((total, file) => total + (jobs[file.id]?.outputSize ?? 0), 0);
    const doneCount = files.filter((file) => jobs[file.id]?.status === 'done').length;

    return {
      inputSize,
      outputSize,
      doneCount,
      totalCount: files.length
    };
  }, [files, jobs]);

  async function addFiles(selectedFiles: MediaFile[]) {
    if (selectedFiles.length === 0) return;

    setFiles((current) => {
      const seen = new Set(current.map((file) => file.path));
      const next = [...current];
      for (const file of selectedFiles) {
        if (!seen.has(file.path)) {
          next.push(file);
          seen.add(file.path);
        }
      }
      return next;
    });

    setJobs((current) => {
      const next = { ...current };
      for (const file of selectedFiles) {
        next[file.id] ??= { status: 'idle', progress: 0 };
      }
      return next;
    });
  }

  async function handlePickFiles() {
    const selectedFiles = await window.vidpress.selectVideos();
    addFiles(selectedFiles);
  }

  async function handleDrop(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setDragActive(false);

    const paths = Array.from(event.dataTransfer.files)
      .map((file) => (file as File & { path?: string }).path)
      .filter(Boolean) as string[];

    if (paths.length > 0) {
      addFiles(await window.vidpress.inspectFiles(paths));
    }
  }

  async function chooseOutputDir() {
    const selectedDir = await window.vidpress.selectOutputFolder();
    if (selectedDir) {
      setOutputDir(selectedDir);
    }
  }

  function removeFile(fileId: string) {
    setFiles((current) => current.filter((file) => file.id !== fileId));
    setJobs((current) => {
      const next = { ...current };
      delete next[fileId];
      return next;
    });
  }

  function clearDone() {
    setFiles((current) => current.filter((file) => jobs[file.id]?.status !== 'done'));
  }

  async function runQueue() {
    if (!engine?.ffmpegReady || files.length === 0 || !outputDir || isRunning) return;

    setIsRunning(true);
    const pendingFiles = files.filter((file) => jobs[file.id]?.status !== 'done');

    setJobs((current) => {
      const next = { ...current };
      for (const file of pendingFiles) {
        next[file.id] = { status: 'queued', progress: 0 };
      }
      return next;
    });

    for (const file of pendingFiles) {
      const jobId = crypto.randomUUID();
      setActiveJobId(jobId);
      setJobs((current) => ({
        ...current,
        [file.id]: { jobId, status: 'running', progress: 0 }
      }));

      const request: CompressionRequest = {
        jobId,
        inputPath: file.path,
        outputDir,
        outputFormat,
        mode,
        preset,
        professional
      };

      try {
        const result = await window.vidpress.startCompression(request);
        setJobs((current) => ({
          ...current,
          [file.id]: {
            jobId,
            status: result.status,
            progress: result.status === 'done' ? 100 : 0,
            outputPath: result.outputPath,
            outputSize: result.outputSize
          }
        }));
      } catch (error) {
        setJobs((current) => ({
          ...current,
          [file.id]: {
            jobId,
            status: 'error',
            progress: 0,
            error: error instanceof Error ? error.message : String(error)
          }
        }));
      }
    }

    setActiveJobId(null);
    setIsRunning(false);
  }

  async function cancelActiveJob() {
    if (activeJobId) {
      await window.vidpress.cancelCompression(activeJobId);
    }
  }

  function resetJobs() {
    setJobs((current) => {
      const next: Record<string, JobState> = {};
      for (const file of files) {
        next[file.id] = current[file.id]?.status === 'running'
          ? current[file.id]
          : { status: 'idle', progress: 0 };
      }
      return next;
    });
  }

  const canStart = Boolean(engine?.ffmpegReady && files.length > 0 && outputDir && !isRunning);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <Clapperboard size={28} aria-hidden="true" />
          <div>
            <h1>VidPress</h1>
            <p>mac 本地视频压缩</p>
          </div>
        </div>

        <div className="engine-status">
          <span className={engine?.ffmpegReady ? 'status-dot ready' : 'status-dot'} />
          <span>{engineStatusText(engine)}</span>
        </div>
      </header>

      <section className="workspace">
        <div className="queue-area">
          <div
            className={`drop-zone ${dragActive ? 'active' : ''}`}
            onDragOver={(event) => {
              event.preventDefault();
              setDragActive(true);
            }}
            onDragLeave={() => setDragActive(false)}
            onDrop={handleDrop}
          >
            <div className="drop-copy">
              <FileVideo size={34} aria-hidden="true" />
              <div>
                <h2>视频队列</h2>
                <p>{files.length ? `${files.length} 个文件，原始 ${formatBytes(totals.inputSize)}` : '拖入视频或选择文件'}</p>
              </div>
            </div>
            <button className="primary-action" type="button" onClick={handlePickFiles}>
              <Plus size={18} aria-hidden="true" />
              添加视频
            </button>
          </div>

          <div className="queue-toolbar">
            <div className="summary-strip">
              <Metric label="完成" value={`${totals.doneCount}/${totals.totalCount}`} />
              <Metric label="导出" value={totals.outputSize ? formatBytes(totals.outputSize) : '-'} />
              <Metric label="节省" value={savingText(totals.inputSize, totals.outputSize)} />
            </div>
            <div className="toolbar-actions">
              <button className="icon-button" type="button" title="重置状态" aria-label="重置状态" onClick={resetJobs}>
                <RotateCcw size={18} aria-hidden="true" />
              </button>
              <button className="icon-button" type="button" title="移除完成项" aria-label="移除完成项" onClick={clearDone}>
                <Trash2 size={18} aria-hidden="true" />
              </button>
            </div>
          </div>

          <div className="file-list">
            {files.length === 0 ? (
              <div className="empty-state">
                <Download size={44} aria-hidden="true" />
                <span>支持 MP4、MOV、MKV、WebM、AVI、WMV、FLV、MPEG、3GP、TS 等常见格式</span>
              </div>
            ) : (
              files.map((file) => (
                <FileRow
                  key={file.id}
                  file={file}
                  job={jobs[file.id] ?? { status: 'idle', progress: 0 }}
                  onRemove={() => removeFile(file.id)}
                />
              ))
            )}
          </div>
        </div>

        <aside className="settings-area">
          <section className="control-section">
            <div className="section-title">
              <Settings2 size={18} aria-hidden="true" />
              <h2>导出</h2>
            </div>

            <label className="field-label" htmlFor="format-select">格式</label>
            <div className="select-wrap">
              <select id="format-select" value={outputFormat} onChange={(event) => setOutputFormat(event.target.value as OutputFormat)}>
                {outputFormats.map((format) => (
                  <option key={format} value={format}>{format.toUpperCase()}</option>
                ))}
              </select>
              <ChevronDown size={16} aria-hidden="true" />
            </div>

            <label className="field-label" htmlFor="output-dir">文件夹</label>
            <div className="path-picker">
              <input id="output-dir" value={outputDir} onChange={(event) => setOutputDir(event.target.value)} />
              <button className="icon-button" type="button" title="选择文件夹" aria-label="选择文件夹" onClick={chooseOutputDir}>
                <FolderOpen size={18} aria-hidden="true" />
              </button>
            </div>
          </section>

          <section className="control-section">
            <div className="section-title">
              <Gauge size={18} aria-hidden="true" />
              <h2>模式</h2>
            </div>

            <div className="segmented" role="tablist" aria-label="压缩模式">
              <button className={mode === 'simple' ? 'selected' : ''} type="button" onClick={() => setMode('simple')}>
                <ShieldCheck size={16} aria-hidden="true" />
                傻瓜
              </button>
              <button className={mode === 'professional' ? 'selected' : ''} type="button" onClick={() => setMode('professional')}>
                <SlidersHorizontal size={16} aria-hidden="true" />
                专业
              </button>
            </div>

            {mode === 'simple' ? (
              <div className="preset-grid">
                {simplePresets.map((item) => (
                  <button
                    className={`preset-button ${preset === item.value ? 'selected' : ''}`}
                    key={item.value}
                    type="button"
                    onClick={() => setPreset(item.value)}
                  >
                    <span>{item.label}</span>
                    <small>{item.detail}</small>
                  </button>
                ))}
              </div>
            ) : (
              <ProfessionalPanel value={professional} onChange={setProfessional} />
            )}
          </section>

          <div className="run-panel">
            {isRunning ? (
              <button className="danger-action" type="button" onClick={cancelActiveJob}>
                <CircleStop size={18} aria-hidden="true" />
                取消当前任务
              </button>
            ) : (
              <button className="primary-action wide" type="button" disabled={!canStart} onClick={runQueue}>
                <Play size={18} aria-hidden="true" />
                开始压缩
              </button>
            )}
          </div>
        </aside>
      </section>
    </main>
  );
}

function ProfessionalPanel({
  value,
  onChange
}: {
  value: ProfessionalSettings;
  onChange: (value: ProfessionalSettings) => void;
}) {
  function patch(next: Partial<ProfessionalSettings>) {
    onChange({ ...value, ...next });
  }

  return (
    <div className="pro-grid">
      <SelectField label="视频编码" value={value.videoCodec} onChange={(next) => patch({ videoCodec: next as ProfessionalSettings['videoCodec'] })}>
        <option value="h264">H.264</option>
        <option value="h265">H.265</option>
        <option value="vp9">VP9</option>
        <option value="av1">AV1</option>
        <option value="mpeg4">MPEG-4</option>
        <option value="copy">复制</option>
      </SelectField>

      <SelectField label="编码速度" value={value.encodingPreset} onChange={(next) => patch({ encodingPreset: next as ProfessionalSettings['encodingPreset'] })}>
        {['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow'].map((encodingPreset) => (
          <option key={encodingPreset} value={encodingPreset}>{encodingPreset}</option>
        ))}
      </SelectField>

      <label className="field-label range-label" htmlFor="crf">CRF <span>{value.crf}</span></label>
      <input id="crf" className="range" type="range" min="0" max="40" value={value.crf} onChange={(event) => patch({ crf: Number(event.target.value) })} />

      <TextField label="视频码率" value={value.videoBitrate} placeholder="例如 2500k" onChange={(next) => patch({ videoBitrate: next })} />

      <SelectField label="分辨率" value={value.resolution} onChange={(next) => patch({ resolution: next as ProfessionalSettings['resolution'] })}>
        <option value="source">原始</option>
        <option value="2160p">2160p</option>
        <option value="1080p">1080p</option>
        <option value="720p">720p</option>
        <option value="480p">480p</option>
        <option value="custom">自定义</option>
      </SelectField>

      {value.resolution === 'custom' && (
        <div className="two-up">
          <NumberField label="宽" value={value.customWidth} onChange={(next) => patch({ customWidth: next })} />
          <NumberField label="高" value={value.customHeight} onChange={(next) => patch({ customHeight: next })} />
        </div>
      )}

      <TextField label="帧率" value={value.fps} placeholder="例如 30" onChange={(next) => patch({ fps: next })} />

      <SelectField label="音频编码" value={value.audioCodec} onChange={(next) => patch({ audioCodec: next as ProfessionalSettings['audioCodec'] })}>
        <option value="aac">AAC</option>
        <option value="opus">Opus</option>
        <option value="mp3">MP3</option>
        <option value="copy">复制</option>
      </SelectField>

      <TextField label="音频码率" value={value.audioBitrate} placeholder="例如 128k" onChange={(next) => patch({ audioBitrate: next })} />

      <label className="toggle-row">
        <input type="checkbox" checked={value.removeAudio} onChange={(event) => patch({ removeAudio: event.target.checked })} />
        <span>移除音频</span>
      </label>
    </div>
  );
}

function FileRow({ file, job, onRemove }: { file: MediaFile; job: JobState; onRemove: () => void }) {
  const done = job.status === 'done';
  const error = job.status === 'error';

  return (
    <article className={`file-row ${done ? 'done' : ''} ${error ? 'error' : ''}`}>
      <div className="file-icon">
        {job.status === 'running' ? <Loader2 size={22} className="spin" aria-hidden="true" /> : <FileVideo size={22} aria-hidden="true" />}
      </div>
      <div className="file-main">
        <div className="file-heading">
          <strong title={file.path}>{file.name}</strong>
          <span>{statusLabel(job.status)}</span>
        </div>
        <div className="file-meta">
          <span>{formatBytes(file.size)}</span>
          {file.duration ? <span>{formatDuration(file.duration)}</span> : null}
          {file.width && file.height ? <span>{file.width}x{file.height}</span> : null}
          {file.videoCodec ? <span>{file.videoCodec}</span> : null}
        </div>
        {job.status === 'running' || job.status === 'queued' ? (
          <div className="progress-line">
            <div style={{ width: `${job.progress}%` }} />
          </div>
        ) : null}
        {job.error ? <p className="error-text">{job.error}</p> : null}
        {done && job.outputSize ? <p className="saving-text">导出 {formatBytes(job.outputSize)}，{savingText(file.size, job.outputSize)}</p> : null}
      </div>
      <div className="file-actions">
        {done && job.outputPath ? (
          <button className="icon-button" type="button" title="在访达中显示" aria-label="在访达中显示" onClick={() => window.vidpress.revealFile(job.outputPath as string)}>
            <FolderOpen size={18} aria-hidden="true" />
          </button>
        ) : null}
        {done ? <CheckCircle2 className="done-mark" size={20} aria-hidden="true" /> : null}
        <button className="icon-button" type="button" title="移除" aria-label="移除" onClick={onRemove}>
          <X size={18} aria-hidden="true" />
        </button>
      </div>
    </article>
  );
}

function SelectField({
  label,
  value,
  onChange,
  children
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  children: ReactNode;
}) {
  const id = `select-${label}`;
  return (
    <div className="field">
      <label className="field-label" htmlFor={id}>{label}</label>
      <div className="select-wrap">
        <select id={id} value={value} onChange={(event) => onChange(event.target.value)}>
          {children}
        </select>
        <ChevronDown size={16} aria-hidden="true" />
      </div>
    </div>
  );
}

function TextField({
  label,
  value,
  placeholder,
  onChange
}: {
  label: string;
  value: string;
  placeholder?: string;
  onChange: (value: string) => void;
}) {
  const id = `text-${label}`;
  return (
    <div className="field">
      <label className="field-label" htmlFor={id}>{label}</label>
      <input id={id} value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} />
    </div>
  );
}

function NumberField({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  const id = `number-${label}`;
  return (
    <div className="field">
      <label className="field-label" htmlFor={id}>{label}</label>
      <input id={id} type="number" min="1" value={value} onChange={(event) => onChange(Number(event.target.value))} />
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function applyProgress(current: Record<string, JobState>, progress: JobProgress) {
  const next = { ...current };
  for (const [fileId, job] of Object.entries(next)) {
    if (job.jobId === progress.jobId) {
      next[fileId] = {
        ...job,
        status: 'running',
        progress: progress.percent,
        speed: progress.speed,
        fps: progress.fps
      };
      break;
    }
  }
  return next;
}

function statusLabel(status: JobStatus) {
  const labels: Record<JobStatus, string> = {
    idle: '待处理',
    queued: '排队中',
    running: '压缩中',
    done: '完成',
    error: '失败',
    cancelled: '已取消'
  };
  return labels[status];
}

function engineStatusText(engine: EngineState | null) {
  if (!engine?.ffmpegReady) {
    return '未找到 FFmpeg';
  }

  const labels = {
    bundled: '内置',
    environment: '环境变量',
    system: '系统'
  };
  return `${engine.ffmpegSource ? labels[engine.ffmpegSource] : ''} FFmpeg 已就绪`;
}

function formatBytes(bytes: number) {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
}

function formatDuration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = Math.round(seconds % 60);
  if (minutes < 60) {
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  const hours = Math.floor(minutes / 60);
  const restMinutes = minutes % 60;
  return `${hours}:${restMinutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
}

function savingText(inputSize: number, outputSize: number) {
  if (!inputSize || !outputSize) return '-';
  const saved = inputSize - outputSize;
  const percent = Math.round((saved / inputSize) * 100);
  return percent >= 0 ? `节省 ${percent}%` : `增加 ${Math.abs(percent)}%`;
}

export default App;

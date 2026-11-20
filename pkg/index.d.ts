/** Loads the emscripten module; `create7zz` from this package is one of these. */
export type ModuleFactory = (options?: {
  stdin?: () => number | null;
  stdout?: (code: number) => void;
  stderr?: (code: number) => void;
  noInitialRun?: boolean;
  locateFile?: (path: string, prefix: string) => string;
  [key: string]: unknown;
}) => Promise<{ FS: unknown; callMain: (argv: string[]) => number }>;

export interface RunInput {
  /** Files written into the sandbox before the run; keys are relative paths. */
  files?: Record<string, Uint8Array | ArrayBuffer | ArrayBufferView | string>;
  /** Bytes fed to `-si`. */
  stdin?: Uint8Array | ArrayBuffer | ArrayBufferView | string;
}

export interface RunResult {
  /** 7zz's process exit code. */
  code: number;
  stdout: string;
  stderr: string;
  /** Files created or changed by this run, keyed by relative path. */
  files: Record<string, Uint8Array>;
}

export interface Api {
  version: string;
  workDir: string;
  run(argv: string[], input?: RunInput): Promise<RunResult>;
}

export function createApi(factory: ModuleFactory, opts?: { workDir?: string; version?: string }): Promise<Api>;

declare const create7zz: ModuleFactory;
export { create7zz };
export default create7zz;

import { spawn, ChildProcess, spawnSync } from 'node:child_process'
import { createWriteStream, existsSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { pipeline } from 'node:stream/promises'

/**
 * Downloads + starts a local PocketBase binary for E2E tests, exposes the URL,
 * and kills the process on teardown. Data directory is wiped on each startup
 * so every test run starts clean.
 */

const PB_VERSION = '0.25.9'
const PB_PORT = 8090
const PB_URL = `http://127.0.0.1:${PB_PORT}`

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)
const E2E_ROOT = resolve(__dirname, '..')
const PB_DIR = join(E2E_ROOT, '.pb-e2e')
const PB_DATA_DIR = join(PB_DIR, 'pb_data')

function platformAsset(): { file: string; binary: string } {
  const platform = process.platform
  const arch = process.arch === 'arm64' ? 'arm64' : 'amd64'
  if (platform === 'win32') {
    return {
      file: `pocketbase_${PB_VERSION}_windows_${arch}.zip`,
      binary: 'pocketbase.exe',
    }
  }
  if (platform === 'darwin') {
    return {
      file: `pocketbase_${PB_VERSION}_darwin_${arch}.zip`,
      binary: 'pocketbase',
    }
  }
  return {
    file: `pocketbase_${PB_VERSION}_linux_${arch}.zip`,
    binary: 'pocketbase',
  }
}

export async function ensurePocketBaseBinary(): Promise<string> {
  const { file, binary } = platformAsset()
  const binaryPath = join(PB_DIR, binary)
  if (existsSync(binaryPath)) return binaryPath

  mkdirSync(PB_DIR, { recursive: true })
  const url = `https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/${file}`
  const zipPath = join(PB_DIR, file)

  console.log(`[pb-e2e] Downloading ${url}`)
  const res = await fetch(url)
  if (!res.ok || !res.body) {
    throw new Error(`PocketBase download failed: ${res.status} ${res.statusText}`)
  }
  await pipeline(res.body as unknown as NodeJS.ReadableStream, createWriteStream(zipPath))

  console.log(`[pb-e2e] Extracting ${file}`)
  if (process.platform === 'win32') {
    const result = spawnSync(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        `Expand-Archive -Force -Path '${zipPath}' -DestinationPath '${PB_DIR}'`,
      ],
      { stdio: 'inherit' },
    )
    if (result.status !== 0) {
      throw new Error('PocketBase extraction failed (powershell Expand-Archive)')
    }
  } else {
    const result = spawnSync('unzip', ['-o', zipPath, '-d', PB_DIR], { stdio: 'inherit' })
    if (result.status !== 0) {
      throw new Error('PocketBase extraction failed (unzip)')
    }
    spawnSync('chmod', ['+x', binaryPath])
  }

  if (!existsSync(binaryPath)) {
    throw new Error(`PocketBase binary missing after extraction: ${binaryPath}`)
  }
  return binaryPath
}

async function waitForReady(url: string, timeoutMs = 20_000): Promise<void> {
  const deadline = Date.now() + timeoutMs
  let lastErr: unknown = null
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${url}/api/health`)
      if (res.ok) return
    } catch (e) {
      lastErr = e
    }
    await new Promise((r) => setTimeout(r, 200))
  }
  throw new Error(`PocketBase did not become ready within ${timeoutMs}ms: ${lastErr}`)
}

let pbProcess: ChildProcess | null = null

/**
 * Wipes the PB data dir so tests start from a clean slate. Call before
 * any CLI or serve action that should see a fresh DB.
 */
export function resetDataDir(): void {
  if (existsSync(PB_DATA_DIR)) {
    rmSync(PB_DATA_DIR, { recursive: true, force: true })
  }
  mkdirSync(PB_DATA_DIR, { recursive: true })
}

export async function startPocketBase(): Promise<string> {
  const binary = await ensurePocketBaseBinary()

  console.log(`[pb-e2e] Starting PocketBase on ${PB_URL}`)
  pbProcess = spawn(
    binary,
    ['serve', '--http', `127.0.0.1:${PB_PORT}`, '--dir', PB_DATA_DIR],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  )

  pbProcess.stdout?.on('data', (chunk) => {
    const line = String(chunk).trim()
    if (line) console.log(`[pb]`, line)
  })
  pbProcess.stderr?.on('data', (chunk) => {
    const line = String(chunk).trim()
    if (line) console.error(`[pb:stderr]`, line)
  })

  pbProcess.on('exit', (code, signal) => {
    if (code != null && code !== 0) {
      console.error(`[pb-e2e] PocketBase exited unexpectedly (code=${code}, signal=${signal})`)
    }
  })

  await waitForReady(PB_URL)
  console.log('[pb-e2e] PocketBase is ready')
  return PB_URL
}

export async function stopPocketBase(): Promise<void> {
  if (!pbProcess) return
  const proc = pbProcess
  pbProcess = null
  await new Promise<void>((resolvePromise) => {
    proc.once('exit', () => resolvePromise())
    proc.kill('SIGTERM')
    // Fallback: force-kill after 3s.
    setTimeout(() => {
      if (!proc.killed) proc.kill('SIGKILL')
    }, 3000)
  })
  console.log('[pb-e2e] PocketBase stopped')
}

export { PB_URL, PB_PORT }

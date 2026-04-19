import PocketBase from 'pocketbase'
import { logWarn, logError } from '@/engine/log-service.ts'

/** PocketBase client singleton. URL configurable via VITE_POCKETBASE_URL env var. */
const pb = new PocketBase(
  import.meta.env.VITE_POCKETBASE_URL ?? 'http://127.0.0.1:8090'
)

// Log PocketBase HTTP errors
pb.afterSend = function (_response: Response, data: unknown) {
  // PocketBase SDK calls afterSend for all responses; errors are thrown separately.
  // We hook here to capture the response data shape for diagnostics.
  return data as ReturnType<typeof Object>
}

// Intercept failed requests via the beforeSend hook to log request context
const originalSend = pb.send.bind(pb)
pb.send = async function (path: string, options?: Record<string, unknown>) {
  try {
    return await originalSend(path, options)
  } catch (e: unknown) {
    const status = (e as { status?: number })?.status
    const msg = (e as { message?: string })?.message ?? String(e)
    if (status && status >= 400 && status < 500) {
      logWarn('PocketBase', `HTTP ${status} on ${path}: ${msg}`)
    } else if (status && status >= 500) {
      logError('PocketBase', `HTTP ${status} on ${path}: ${msg}`, e)
    }
    throw e
  }
}

export default pb

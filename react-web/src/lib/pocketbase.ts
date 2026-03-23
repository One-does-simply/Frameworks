import PocketBase from 'pocketbase'

/** PocketBase client singleton. URL configurable via VITE_POCKETBASE_URL env var. */
const pb = new PocketBase(
  import.meta.env.VITE_POCKETBASE_URL ?? 'http://127.0.0.1:8090'
)

export default pb

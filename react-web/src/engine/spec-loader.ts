/**
 * Simple spec loading utilities for ODS React web.
 *
 * Three entry points for getting a spec JSON string:
 *   - loadFromFile: reads from a File object (e.g., file input or drag-drop)
 *   - loadFromUrl: fetches from a URL
 *   - loadFromText: passthrough with basic validation
 */

/**
 * Reads a File object and returns its text content.
 * Throws if the file cannot be read.
 */
export async function loadFromFile(file: File): Promise<string> {
  if (file.size > 10_000_000) {
    throw new Error('File too large (max 10MB)')
  }
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      if (typeof reader.result === 'string') {
        resolve(reader.result)
      } else {
        reject(new Error('Failed to read file as text'))
      }
    }
    reader.onerror = () => {
      reject(new Error(`Failed to read file: ${reader.error?.message ?? 'unknown error'}`))
    }
    reader.readAsText(file)
  })
}

/**
 * Fetches a spec from a URL and returns it as a string.
 * Throws if the fetch fails or returns a non-OK status.
 */
export async function loadFromUrl(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Failed to fetch spec from ${url}: ${response.status} ${response.statusText}`)
  }
  return response.text()
}

/**
 * Passthrough loader for raw text input.
 * Validates that the input is a non-empty string, then returns it unchanged.
 */
export function loadFromText(text: string): string {
  if (typeof text !== 'string') {
    throw new Error('Expected a string')
  }
  if (text.trim() === '') {
    throw new Error('Spec text is empty')
  }
  return text
}

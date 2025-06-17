import { decompress } from 'jsr:@fakoua/zip-ts@1.3.1'
import { existsSync } from 'jsr:@std/fs@^1.0.8'

export type Release = {
  id: number
  url: string
  assets_url: string
  tag_name: string
  name: string
  draft: boolean
  prerelease: boolean
  assets: Asset[]
}

export type Asset = {
  id: number
  url: string
  browser_download_url: string
  name: string
  state: 'uploaded' | 'open'
  content_type: string
  size: number
}

const DEBUG = Deno.env.get('FENV_DEBUG') === '1'

const GITHUB_TOKEN = Deno.env.get('GITHUB_TOKEN') ||
  Deno.env.get('GH_TOKEN') || ''

const authHeader: {
  Authorization?: string
} = GITHUB_TOKEN ? { 'Authorization': `Bearer ${GITHUB_TOKEN}` } : {}

export async function getRelease(
  option?: { tag?: string },
): Promise<Release> {
  const response = await fetch(
    'https://api.github.com/repos/fenv-org/fenv/releases' +
      (option?.tag ? `/tags/${option.tag}` : '/latest'),
    {
      headers: {
        ...authHeader,
        'accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    },
  )

  if (!response.ok) {
    throw new Error(
      `Failed to fetch releases: ${response.status}`,
      { cause: response },
    )
  }

  return await response.json()
}

export async function downloadZipAsset(
  asset: { browser_download_url: string },
  destination: string,
): Promise<void> {
  const response = await fetch(asset.browser_download_url, {
    headers: {
      ...authHeader,
    },
  })
  if (!response.ok) {
    throw new Error(
      `Failed to fetch asset: ${response.status}: ${response.statusText}`,
      { cause: response },
    )
  }

  const tempFile = await Deno.makeTempFile({ suffix: '.zip' })
  try {
    const blob = await response.blob()
    await Deno.writeFile(tempFile, blob.stream())
    if (DEBUG) {
      console.error(`Downloaded asset to: ${tempFile}`)
    }
    if (existsSync(destination)) {
      if (DEBUG) {
        console.error(`Recreating destination: ${destination}`)
      }
      Deno.removeSync(destination)
      Deno.mkdirSync(destination, { recursive: true })
    }
    if (DEBUG) {
      console.error(`Decompressing asset to: ${destination}`)
    }
    const result = await decompress(tempFile, destination)
    if (DEBUG) {
      console.error(`Decompressed asset to: ${result}`)
    }
  } finally {
    Deno.removeSync(tempFile)
  }
}

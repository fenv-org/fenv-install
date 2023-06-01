import { decompress } from 'https://deno.land/x/zip@v1.2.5/mod.ts'

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

export async function getRelease(
  option?: { tag?: string },
): Promise<Release> {
  const response = await fetch(
    'https://api.github.com/repos/fenv-org/fenv/releases' +
      (option?.tag ? `/tags/${option.tag}` : '/latest'),
    {
      headers: {
        'accept': 'application/vnd.github+json',
        'x-github0api-version': '2022-11-28',
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
  const response = await fetch(asset.browser_download_url)
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
    await decompress(tempFile, destination)
  } finally {
    Deno.removeSync(tempFile)
  }
}

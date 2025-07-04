// deno-lint-ignore-file no-explicit-any

import * as fs from 'jsr:@std/fs@^1.0.8'
import {
  Asset,
  downloadZipAsset,
  getRelease,
  Release,
} from './module/fenv-release.ts'

const DEBUG = Deno.env.get('FENV_DEBUG') === '1'

async function main() {
  const version: string | undefined = Deno.args.length > 0
    ? Deno.args[0]
    : undefined

  let release: Release
  try {
    release = await getRelease({ tag: version })
    console.error('fenv-init: Found release:', release.tag_name)
  } catch (e: any) {
    if (e && e.cause?.status === 404) {
      console.error('fenv-init: No release found:', version)
      Deno.exit(1)
    } else {
      console.error('fenv-init: Failed to fetch releases:', e.message)
      Deno.exit(2)
    }
  }

  verbose('Checking host:', {
    arch: Deno.build.arch,
    os: Deno.build.os,
  })
  const assetArch = Deno.build.arch
  const assetOs = Deno.build.os === 'darwin'
    ? 'apple-darwin'
    : Deno.build.os === 'linux'
    ? 'unknown-linux-musl'
    : Deno.exit(3)

  const assetName = `fenv-${assetArch}-${assetOs}.zip`
  const asset = release
    .assets
    .find((asset) => asset.name === assetName)

  if (!asset) {
    console.error('fenv-init: No asset found:', assetName)
    Deno.exit(4)
  }

  console.error(`Found asset: ${asset.browser_download_url}`)
  await downloadAsset(asset)
}

function verbose(...data: any[]) {
  if (DEBUG) console.error(...data)
}

const downloadAsset = async (asset: Asset) => {
  const fenvRoot = Deno.env.get('FENV_ROOT') ??
    `${Deno.env.get('HOME')}/.fenv`
  const fenvBin = `${fenvRoot}/bin`
  fs.ensureDirSync(fenvBin)

  try {
    await downloadZipAsset(asset, fenvBin)
    verbose(`Downloaded asset to: `, fenvBin)
  } catch (e: any) {
    console.error('fenv-init:', e.message)
    Deno.exit(5)
  }
}

await main()

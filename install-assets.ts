import * as fs from 'https://deno.land/std@0.190.0/fs/mod.ts'
import { Asset, downloadZipAsset, getRelease, Release } from './fenv-release.ts'

const DEBUG = Deno.env.get('FENV_DEBUG') === '1'

async function main() {
  const version: string | undefined = Deno.args.length > 0
    ? Deno.args[0]
    : undefined

  let release: Release
  try {
    release = await getRelease({ tag: version })
    console.error('fenv-init: Found release:', release.tag_name)
  } catch (e) {
    if (e.cause?.status === 404) {
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

// deno-lint-ignore no-explicit-any
function verbose(...data: any[]) {
  if (DEBUG) console.error(...data)
}

const downloadAsset = async (asset: Asset) => {
  const fenvRoot = Deno.env.get('FENV_ROOT') ??
    `${Deno.env.get('HOME')}/.fenv`
  const fenvBin = `${fenvRoot}/bin`
  if (!fs.existsSync(fenvBin)) {
    Deno.mkdirSync(fenvBin, { recursive: true })
  }

  try {
    await downloadZipAsset(asset, fenvBin)
    verbose(`Downloaded asset to: `, fenvBin)
  } catch (e) {
    console.error('fenv-init:', e.message)
    Deno.exit(5)
  }
}

await main()

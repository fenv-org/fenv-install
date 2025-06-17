// deno-lint-ignore-file no-explicit-any

import $ from 'jsr:@david/dax@0.43.2'
import { getRelease, Release } from './module/fenv-release.ts'
import { join } from 'jsr:@std/path@^1.1.0'
import { ensureDirSync } from 'jsr:@std/fs@^1.0.8'

const BASE_URL = 'https://raw.githubusercontent.com/fenv-org/fenv' as const

async function main() {
  const fenvHome = Deno.args[0]
  const version: string | undefined = Deno.args.length > 1
    ? Deno.args[1]
    : undefined

  let release: Release
  try {
    release = await getRelease({ tag: version })
  } catch (e: any) {
    if (e.cause?.status === 404) {
      console.error('fenv-init: No release found:', version)
      Deno.exit(1)
    } else {
      console.error('fenv-init: Failed to fetch releases:', e.message)
      Deno.exit(2)
    }
  }

  const tag = release.tag_name

  const shims = [
    'shims/flutter',
    'shims/dart',
  ]
  Deno.removeSync(join(fenvHome, 'shims'), { recursive: true })
  ensureDirSync(join(fenvHome, 'shims'))
  ensureDirSync(join(fenvHome, 'versions'))
  for (const shim of shims) {
    await $`curl -fsSL "${BASE_URL}/${tag}/${shim}" -o "${
      $.path(join(fenvHome, shim))
    }"`.stderr('null')
    await $`chmod a+x "${$.path(join(fenvHome, shim))}"`
  }
}

main()

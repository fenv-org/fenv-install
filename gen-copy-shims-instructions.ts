// deno-lint-ignore-file no-explicit-any

import { getRelease, Release } from './module/fenv-release.ts'

const BASE_URL = 'https://raw.githubusercontent.com/fenv-org/fenv'

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
  console.log(`rm -rf ${fenvHome}/shims`)
  console.log(`mkdir -p ${fenvHome}/{shims,versions}`)
  console.log('for command in shims/flutter shims/dart; do')
  console.log('  curl -fsSL \\')
  console.log(`    "${BASE_URL}/${tag}/$command" \\`)
  console.log(`    -o "${fenvHome}/$command"`)
  console.log(`  chmod a+x "${fenvHome}/$command"`)
  console.log('done')
}

main()

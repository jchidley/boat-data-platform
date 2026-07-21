import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

test('--pi5-host reaches the underlying health check environment and Signal K URL', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'boat-health-host-'))
  const capture = path.join(dir, 'environment.txt')
  const fakeBash = path.join(dir, 'bash')
  fs.writeFileSync(fakeBash, `#!/bin/sh\nprintf 'PI5_HOST=%s\\nPI5_SIGNALK_URL=%s\\n' "$PI5_HOST" "$PI5_SIGNALK_URL" > "$CAPTURE_FILE"\nprintf 'PASS synthetic health check\\n'\n`)
  fs.chmodSync(fakeBash, 0o755)

  try {
    const result = spawnSync(process.execPath, [
      'scripts/collect-steady-state-health.mjs',
      '--sample-sec', '1',
      '--pi5-host', 'test-pi5.local',
      '--print-only'
    ], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${dir}:${process.env.PATH}`,
        CAPTURE_FILE: capture,
        PI5_SIGNALK_URL: ''
      }
    })

    assert.equal(result.status, 0, result.stderr)
    assert.equal(fs.readFileSync(capture, 'utf8'),
      'PI5_HOST=test-pi5.local\nPI5_SIGNALK_URL=http://test-pi5.local:3001\n')
    assert.match(result.stdout, /PASS synthetic health check/)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

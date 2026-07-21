import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const install = fs.readFileSync('infra/pi5nvme/install-pi5nvme.sh', 'utf8')
const masterbusInstall = fs.readFileSync('infra/pi5nvme/install-masterbus-tools.sh', 'utf8')
const nativeDropin = fs.readFileSync('infra/pi5nvme/systemd/masterbus-signalk-native.conf', 'utf8')
const nativePatch = fs.readFileSync('infra/pi5nvme/masterbus/masterbus-signalk-alternator-mapping.patch', 'utf8')
const logrotate = fs.readFileSync('infra/pi5nvme/logrotate/boat-masterbus-native-events', 'utf8')
const storageGuard = fs.readFileSync('infra/pi5nvme/scripts/check-derived-storage-pressure.sh', 'utf8')
const storageGuardTimer = fs.readFileSync('infra/pi5nvme/systemd/boat-derived-storage-guard.timer', 'utf8')
const healthCheck = fs.readFileSync('scripts/check-steady-state.sh', 'utf8')

test('committed infrastructure shell scripts pass bash syntax validation', () => {
  const scripts = execFileSync('git', ['ls-files', 'infra/**/*.sh', 'scripts/*.sh'], { encoding: 'utf8' })
    .trim()
    .split('\n')
    .filter(Boolean)

  assert.ok(scripts.includes('infra/pi5nvme/scripts/check-pi5-boat-health.sh'))
  for (const script of scripts) execFileSync('bash', ['-n', script])
})

test('MasterBus installer deploys native decoded event logging in the single USB owner', () => {
  assert.match(masterbusInstall, /masterbus-signalk-native\.conf/)
  assert.match(masterbusInstall, /\/srv\/boat\/masterbus\/native-events/)
  assert.match(nativeDropin, /MASTERBUS_NATIVE_LOG_DIR=\/srv\/boat\/masterbus\/native-events/)
  assert.match(nativeDropin, /ReadWritePaths=\/srv\/boat\/masterbus\/native-events/)
  assert.match(nativePatch, /masterbus-native-event-v1/)
  assert.match(nativePatch, /masterbus-native-\{hour\}0000Z\.jsonl/)
  assert.match(nativePatch, /if hour != self\.hour/)
  assert.match(nativePatch, /new MasterBus device appeared; restarting discovery/)
  assert.match(install, /disable --now boat-masterbus-signalk-log\.service/)
})

test('pi5 installer enforces the two-path service layout and fails fast on SQL errors', () => {
  assert.match(install, /disable --now boat-signalk-collector\.service/)
  assert.match(install, /rm -f \/etc\/systemd\/system\/boat-signalk-collector\.service/)
  assert.match(install, /psql -X -v ON_ERROR_STOP=1 -d boatdata -f/)
})

test('derived storage guard enforces the 85 percent threshold without touching raw acquisition', () => {
  assert.match(storageGuard, /STOP_PCT=\$\{STOP_PCT:-85\}/)
  assert.match(storageGuard, /DERIVED_UNITS=\$\{DERIVED_UNITS:-\}/)
  assert.doesNotMatch(storageGuard, /boat-n2k-raw-receiver/)
  assert.match(storageGuardTimer, /OnUnitActiveSec=5min/)
  assert.match(install, /boat-derived-storage-guard\.timer/)
})

test('health check monitors the known NVMe and MasterBus USB failure modes', () => {
  assert.match(healthCheck, /nvme_core\.default_ps_max_latency_us=0/)
  assert.match(healthCheck, /pcie_aspm=off/)
  assert.match(healthCheck, /pcie_port_pm=off/)
  assert.match(healthCheck, /1a64:0000.*MasterBus/)
  assert.match(healthCheck, /CSTS=0xffffffff/)
  assert.match(healthCheck, /EXT4-fs error.*nvme/)
})

test('native MasterBus JSONL logrotate compresses replay logs without deleting recent history', () => {
  assert.match(logrotate, /\/srv\/boat\/masterbus\/native-events\/\*\.jsonl/)
  assert.match(logrotate, /daily/)
  assert.match(logrotate, /rotate 90/)
  assert.match(logrotate, /compress/)
  assert.match(logrotate, /copytruncate/)
})

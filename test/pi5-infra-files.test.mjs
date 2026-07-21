import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const install = fs.readFileSync('infra/pi5nvme/install-pi5nvme.sh', 'utf8')
const service = fs.readFileSync('infra/pi5nvme/systemd/boat-masterbus-signalk-log.service', 'utf8')
const logrotate = fs.readFileSync('infra/pi5nvme/logrotate/boat-masterbus-signalk-jsonl', 'utf8')
const storageGuard = fs.readFileSync('infra/pi5nvme/scripts/check-derived-storage-pressure.sh', 'utf8')
const storageGuardTimer = fs.readFileSync('infra/pi5nvme/systemd/boat-derived-storage-guard.timer', 'utf8')

test('pi5 installer installs and enables MasterBus replay logger safely', () => {
  assert.match(install, /boat-masterbus-signalk-log\.service/)
  assert.match(install, /boat-masterbus-signalk-jsonl/)
  assert.match(install, /\/srv\/boat\/masterbus\/signalk-jsonl/)
})

test('MasterBus replay logger service writes JSONL as unprivileged jack user', () => {
  assert.match(service, /User=jack/)
  assert.match(service, /MASTERBUS_LOG_DIR=\/srv\/boat\/masterbus\/signalk-jsonl/)
  assert.match(service, /ExecStart=\/usr\/bin\/npm run collect:masterbus-log/)
  assert.match(service, /Restart=always/)
  assert.match(service, /NoNewPrivileges=true/)
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

test('MasterBus JSONL logrotate compresses replay logs without deleting recent history', () => {
  assert.match(logrotate, /\/srv\/boat\/masterbus\/signalk-jsonl\/\*\.jsonl/)
  assert.match(logrotate, /rotate 90/)
  assert.match(logrotate, /compress/)
  assert.match(logrotate, /copytruncate/)
})

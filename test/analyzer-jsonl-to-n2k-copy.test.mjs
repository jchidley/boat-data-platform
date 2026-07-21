import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const script = path.resolve('scripts/analyzer-jsonl-to-n2k-copy.mjs')

function runFixture(input, extraArgs = []) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'n2k-copy-test-'))
  const frames = path.join(dir, 'frames.tsv')
  const fields = path.join(dir, 'fields.tsv')
  const typedDir = path.join(dir, 'typed')
  const result = spawnSync(process.execPath, [script, '--log-file-id', '42', '--frames-tsv', frames, '--fields-tsv', fields, ...extraArgs], {
    input,
    encoding: 'utf8'
  })
  return { dir, frames, fields, typedDir, result }
}

test('converts analyzer JSONL to relational COPY TSV', () => {
  const input = [
    JSON.stringify({
      input: ['(1783263600.125000) can0 09F8017F#0102030405060708'],
      timestamp: '2026-07-04T00:00:00.000Z',
      pgn: 129025,
      prio: 2,
      src: 127,
      dst: 255,
      id: '0x09F8017F',
      fields: { Latitude: 52.1234567, Longitude: -1.2345678 }
    }),
    JSON.stringify({
      input: ['(1783263601.500000) can0 15FD0204#1122334455667788'],
      pgn: 130306,
      src: 4,
      fields: { Wind: { Speed: 7.5, Angle: 1.2 }, Reference: 'Apparent', Valid: true }
    })
  ].join('\n') + '\n'

  const { frames, fields, result } = runFixture(input, ['--research-mode', 'selected', '--research-pgn', '129025,130306'])
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stderr, /"framesWritten":2/)
  assert.match(result.stderr, /"fieldsWritten":6/)

  const frameRows = fs.readFileSync(frames, 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.equal(frameRows.length, 2)
  assert.deepEqual(frameRows[0], ['42', '0', '2026-07-05T15:00:00.125Z', '129025', '127', '255', '2', String(Number.parseInt('09F8017F', 16))])
  assert.deepEqual(frameRows[1].slice(0, 6), ['42', '1', '2026-07-05T15:00:01.500Z', '130306', '4', '\\N'])
  assert.equal(frameRows[1][6], '\\N')

  const fieldRows = fs.readFileSync(fields, 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.equal(fieldRows.length, 6)
  assert.deepEqual(fieldRows.map(r => r[5]).sort(), ['Latitude', 'Longitude', 'Reference', 'Valid', 'Wind.Angle', 'Wind.Speed'].sort())
  const speed = fieldRows.find(r => r[5] === 'Wind.Speed')
  assert.equal(speed[6], '7.5')
  assert.equal(speed[7], '\\N')
  assert.equal(speed[8], '\\N')
  const reference = fieldRows.find(r => r[5] === 'Reference')
  assert.equal(reference[6], '\\N')
  assert.equal(reference[7], 'Apparent')
  const valid = fieldRows.find(r => r[5] === 'Valid')
  assert.equal(valid[8], 'true')
})

test('research output is empty by default', () => {
  const input = JSON.stringify({
    input: ['(1783263600.125000) can0 09F8017F#0102030405060708'],
    pgn: 129025,
    src: 127,
    fields: { Latitude: 52.1, Longitude: -1.2 }
  }) + '\n'
  const { fields, result } = runFixture(input)
  assert.equal(result.status, 0, result.stderr)
  assert.equal(fs.readFileSync(fields, 'utf8'), '')
  assert.match(result.stderr, /"researchMode":"none"/)
  assert.match(result.stderr, /"fieldsWritten":0/)
})

test('untyped research mode excludes PGNs with typed models', () => {
  const input = [
    JSON.stringify({ input: ['(1783263600.125000) can0 09F8017F#01'], pgn: 129025, fields: { Latitude: 52.1 } }),
    JSON.stringify({ input: ['(1783263601.125000) can0 19FFFD01#01'], pgn: 131069, fields: { Mystery: 7 } })
  ].join('\n') + '\n'
  const { fields, result } = runFixture(input, ['--research-mode', 'untyped'])
  assert.equal(result.status, 0, result.stderr)
  const rows = fs.readFileSync(fields, 'utf8').trim().split('\n')
  assert.equal(rows.length, 1)
  assert.match(rows[0], /131069.*Mystery/)
})

test('writes PGN-shaped typed TSV rows when requested', () => {
  const input = [
    JSON.stringify({
      input: ['(1783263600.125000) can0 09F8017F#0102030405060708'],
      pgn: 129025,
      src: 127,
      fields: { Latitude: 52.1234567, Longitude: -1.2345678 }
    }),
    JSON.stringify({
      input: ['(1783263601.500000) can0 15FD0204#1122334455667788'],
      pgn: 130306,
      src: 4,
      fields: { SID: 9, 'Wind Speed': 7.5, 'Wind Angle': 1.2, Reference: 'Apparent' }
    }),
    JSON.stringify({
      input: ['(1783263602.000000) can0 09F11274#1122334455667788'],
      pgn: 127250,
      src: 116,
      fields: { SID: 3, Heading: 1.5, Deviation: 0.01, Variation: -0.02, Reference: 'Magnetic' }
    }),
    JSON.stringify({
      input: ['(1783263603.000000) can0 09F10D06#FF07FF7FC501FFFF'],
      pgn: 127245,
      src: 6,
      fields: { Instance: 1, 'Direction Order': 'Move to port', 'Angle Order': 0.02, Position: 0.0453 }
    }),
    JSON.stringify({
      input: ['(1783263604.000000) can0 0DF1130A#004F300F002702FF'],
      pgn: 127251,
      src: 10,
      fields: { SID: 0, Rate: 0.03110647 }
    }),
    JSON.stringify({
      input: ['(1783263604.500000) can0 0DF20D04#0001000000000000'],
      pgn: 127501,
      src: 4,
      fields: { Instance: 0, Indicator1: 'On', Indicator2: 'Off', Indicator28: 'Error' }
    }),
    JSON.stringify({
      input: ['(1783263605.000000) can0 0DF1190A#00FF7F2BFF9BFFFF'],
      pgn: 127257,
      src: 10,
      fields: { SID: 0, Pitch: -0.0213, Roll: -0.0101 }
    }),
    JSON.stringify({
      input: ['(1783263606.000000) can0 19F11A16#14F8FFFF9DFBFFFF'],
      pgn: 127258,
      src: 22,
      fields: { SID: 20, Source: 'WMM 2020', Variation: -0.1123 }
    }),
    JSON.stringify({
      input: ['(1783263606.500000) can0 19FA030B#18D73C006400FF7F'],
      pgn: 129539,
      src: 11,
      fields: { SID: 24, 'Desired Mode': '3D', 'Actual Mode': '3D', HDOP: 0.6, VDOP: 1, TDOP: 1.2 }
    }),
    JSON.stringify({
      input: ['(1783263606.750000) can0 19FA040B#409318FE0C01A20D'],
      pgn: 129540,
      src: 11,
      fields: { SID: 24, 'Range Residual Mode': 2, 'Sats in View': 2, list: [
        { PRN: 1, Elevation: 0.349, Azimuth: 0.925, SNR: 45, 'Range residuals': 0, Status: 'Used' },
        { PRN: 3, Elevation: 0.7853, Azimuth: 0.7504, SNR: 43, 'Range residuals': 0.1, Status: 'Used' }
      ] }
    }),
    JSON.stringify({
      input: ['(1783263606.800000) can0 09F10504#0015300C5F5D01D1'],
      pgn: 127237,
      src: 4,
      fields: { 'Rudder Limit Exceeded': 'No', 'Off-Heading Limit Exceeded': 'No', Override: 'No', 'Steering Mode': 'Heading Control', 'Turn Mode': 'Turn rate controlled', 'Heading Reference': 'True', 'Commanded Rudder Direction': 'Move to port', 'Commanded Rudder Angle': 0.0349, 'Heading-To-Steer (Course)': 0.9425, 'Rudder Limit': 0.4363, 'Off-Heading Limit': 0.3491, 'Rate of Turn Order': 0.06981 }
    }),
    JSON.stringify({
      input: ['(1783263606.850000) can0 0DF9040C#40229EFFFFFFFFFF'],
      pgn: 129284,
      src: 12,
      fields: { SID: 158, 'Distance to Waypoint': 1234.5, 'Course/Bearing reference': 'True', 'Arrival Circle Entered': 'No', 'Calculation Type': 'Great Circle', 'ETA Time': '12:34:56', 'ETA Date': '2026-07-05', 'Bearing, Position to Destination Waypoint': 1.23, 'Destination Waypoint Number': 7, 'Destination Latitude': 52.1, 'Destination Longitude': -1.2, 'Waypoint Closing Velocity': 3.4 }
    }),
    JSON.stringify({
      input: ['(1783263606.900000) can0 1DF9050C#C027FFFF0200FFFF'],
      pgn: 129285,
      src: 12,
      fields: { 'Start RPS#': 0, nItems: 2, 'Database ID': 1, 'Route ID': 3, 'Navigation direction in route': 'Forward', 'Supplementary Route/WP data available': 'Off', 'Route Name': 'Test Route', list: [
        { 'WP ID': 10, 'WP Name': 'A', 'WP Latitude': 52.11, 'WP Longitude': -1.21 },
        { 'WP ID': 11, 'WP Name': 'B', 'WP Latitude': 52.12, 'WP Longitude': -1.22 }
      ] }
    }),
    JSON.stringify({
      input: ['(1783263606.910000) can0 11F80E16#601C01076C1120F8'],
      pgn: 129038,
      src: 22,
      fields: { 'Message ID': 'Scheduled Class A position report', 'Repeat Indicator': 'Initial', 'User ID': 538012679, Longitude: 132.30318, Latitude: 28.2842716, 'Position Accuracy': 'Low', RAIM: 'not in use', 'Time Stamp': '54', COG: 5.4897, SOG: 8.48, 'Communication State': 229398, 'AIS Transceiver information': 'Channel B VDL reception', Heading: 5.4967, 'Rate of Turn': 0, 'Nav Status': 'Under way using engine', 'Special Maneuver Indicator': 'Not available', 'Sequence ID': 1 }
    }),
    JSON.stringify({
      input: ['(1783263606.920000) can0 15F80F16#1122334455667788'],
      pgn: 129039,
      src: 22,
      fields: { 'Message ID': 'Standard Class B position report', 'Repeat Indicator': 'Initial', 'User ID': 235123456, Longitude: -1.1, Latitude: 50.1, 'Position Accuracy': 'High', RAIM: 'in use', 'Time Stamp': '12', COG: 1.2, SOG: 3.4, 'Communication State': 123, 'AIS Transceiver information': 'Channel A VDL reception', Heading: 1.3, 'Unit type': 'SOTDMA', 'Integrated Display': 'Yes', DSC: 'Yes', Band: 'Entire marine band', 'Can handle Msg 22': 'Yes', 'AIS mode': 'Autonomous', 'AIS communication state': 'SOTDMA' }
    }),
    JSON.stringify({
      input: ['(1783263606.930000) can0 19FB0216#404C05076C1120A4'],
      pgn: 129794,
      src: 22,
      fields: { 'Message ID': 'Static and voyage related data', 'Repeat Indicator': 'Initial', 'User ID': 538012679, 'IMO number': 9169316, Callsign: 'V7B3189', Name: 'GRAND CHOICE', 'Type of ship': 'Cargo ship', Length: 179, Beam: 33, 'Position reference from Starboard': 10, 'Position reference from Bow': 49, 'ETA Date': '2026.07.06', 'ETA Time': '21:00:00', Draft: 6.9, Destination: 'KR USN', 'AIS version indicator': 'ITU-R M.1371-5', 'GNSS type': 'GPS', DTE: 'Available', 'AIS Transceiver information': 'Channel A VDL reception' }
    }),
    JSON.stringify({
      input: ['(1783263606.940000) can0 19FB1116#1122334455667788'],
      pgn: 129809,
      src: 22,
      fields: { 'Message ID': 'Static data report', 'Repeat Indicator': 'Initial', 'User ID': 235123456, Name: 'CLASS B BOAT', 'AIS Transceiver information': 'Channel A VDL reception', 'Sequence ID': 2 }
    }),
    JSON.stringify({
      input: ['(1783263606.950000) can0 19FB1216#1122334455667788'],
      pgn: 129810,
      src: 22,
      fields: { 'Message ID': 'Static data report', 'Repeat Indicator': 'Initial', 'User ID': 235123456, 'Type of ship': 'Sailing', 'Vendor ID': 'ABC123', Callsign: 'MABC7', Length: 12.3, Beam: 4.5, 'Position reference from Starboard': 2.1, 'Position reference from Bow': 3.2, 'Mothership User ID': 0, 'GNSS type': 'GPS', 'AIS Transceiver information': 'Channel B VDL reception', 'Sequence ID': 2 }
    }),
    JSON.stringify({
      input: ['(1783263607.000000) can0 19FD0604#1122334455667788'],
      pgn: 130310,
      src: 4,
      fields: { SID: 2, 'Water Temperature': 291.15, 'Outside Ambient Air Temperature': 293.15, 'Atmospheric Pressure': 101325 }
    }),
    JSON.stringify({
      input: ['(1783263608.000000) can0 19FD0704#1122334455667788'],
      pgn: 130311,
      src: 4,
      fields: { SID: 3, 'Temperature Source': 'Sea Temperature', 'Humidity Source': 'Inside', Temperature: 292.15, Humidity: 0.67, 'Atmospheric Pressure': 101000 }
    }),
    JSON.stringify({
      input: ['(1783263609.000000) can0 19FD0804#1122334455667788'],
      pgn: 130312,
      src: 4,
      fields: { SID: 4, Instance: 1, Source: 'Sea Temperature', 'Actual Temperature': 289.15, 'Set Temperature': 290.15 }
    }),
    JSON.stringify({
      input: ['(1783263610.000000) can0 19FD0A16#1122334455667788'],
      pgn: 130314,
      src: 22,
      fields: { SID: 5, Instance: 0, Source: 'Atmospheric', Pressure: 100900 }
    }),
    JSON.stringify({
      input: ['(1783263611.000000) can0 19FD0C23#1122334455667788'],
      pgn: 130316,
      src: 35,
      fields: { SID: 6, Instance: 2, Source: 'Sea Temperature', Temperature: 288.15, 'Set Temperature': 289.15 }
    })
  ].join('\n') + '\n'

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'n2k-copy-typed-test-'))
  const typedDir = path.join(temp, 'typed')
  const { result } = runFixture(input, ['--typed-dir', typedDir])
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stderr, /"typedWritten":25/)

  const position = fs.readFileSync(path.join(typedDir, 'n2k_position_rapid_129025_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(position, ['42', '0', '2026-07-05T15:00:00.125Z', '127', '52.1234567', '-1.2345678'])

  const wind = fs.readFileSync(path.join(typedDir, 'n2k_wind_130306_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(wind, ['42', '1', '2026-07-05T15:00:01.500Z', '4', '9', '7.5', '1.2', 'Apparent'])

  const heading = fs.readFileSync(path.join(typedDir, 'n2k_heading_127250_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(heading, ['42', '2', '2026-07-05T15:00:02.000Z', '116', '3', '1.5', '0.01', '-0.02', 'Magnetic'])

  const rudder = fs.readFileSync(path.join(typedDir, 'n2k_rudder_127245_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(rudder, ['42', '3', '2026-07-05T15:00:03.000Z', '6', '1', 'Move to port', '0.02', '0.0453'])

  const rateOfTurn = fs.readFileSync(path.join(typedDir, 'n2k_rate_of_turn_127251_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(rateOfTurn, ['42', '4', '2026-07-05T15:00:04.000Z', '10', '0', '0.03110647'])

  const switchBank = fs.readFileSync(path.join(typedDir, 'n2k_switch_bank_status_127501_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.equal(switchBank.length, 33)
  assert.deepEqual(switchBank.slice(0, 7), ['42', '5', '2026-07-05T15:00:04.500Z', '4', '0', 'On', 'Off'])
  assert.equal(switchBank[32], 'Error')

  const attitude = fs.readFileSync(path.join(typedDir, 'n2k_attitude_127257_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(attitude, ['42', '6', '2026-07-05T15:00:05.000Z', '10', '0', '\\N', '-0.0213', '-0.0101'])

  const magneticVariation = fs.readFileSync(path.join(typedDir, 'n2k_magnetic_variation_127258_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(magneticVariation, ['42', '7', '2026-07-05T15:00:06.000Z', '22', '20', 'WMM 2020', '-0.1123'])

  const dops = fs.readFileSync(path.join(typedDir, 'n2k_gnss_dops_129539_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(dops, ['42', '8', '2026-07-05T15:00:06.500Z', '11', '24', '3D', '3D', '0.6', '1', '1.2'])

  const satellites = fs.readFileSync(path.join(typedDir, 'n2k_gnss_satellites_129540_stage_v2.tsv'), 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.deepEqual(satellites[0], ['42', '9', '2026-07-05T15:00:06.750Z', '11', '24', '2', '2', '0', '1', '0.349', '0.925', '45', '0', 'Used'])
  assert.deepEqual(satellites[1], ['42', '9', '2026-07-05T15:00:06.750Z', '11', '24', '2', '2', '1', '3', '0.7853', '0.7504', '43', '0.1', 'Used'])

  const headingTrackControl = fs.readFileSync(path.join(typedDir, 'n2k_heading_track_control_127237_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(headingTrackControl, ['42', '10', '2026-07-05T15:00:06.800Z', '4', 'No', 'No', '\\N', 'No', 'Heading Control', 'Turn rate controlled', 'True', 'Move to port', '0.0349', '0.9425', '\\N', '0.4363', '0.3491', '\\N', '0.06981', '\\N', '\\N'])

  const navigationData = fs.readFileSync(path.join(typedDir, 'n2k_navigation_data_129284_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(navigationData, ['42', '11', '2026-07-05T15:00:06.850Z', '12', '158', '1234.5', 'True', '\\N', 'No', 'Great Circle', '45296', '20639', '\\N', '1.23', '\\N', '7', '52.1', '-1.2', '3.4'])

  const routeWaypoints = fs.readFileSync(path.join(typedDir, 'n2k_route_waypoint_129285_stage_v2.tsv'), 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.deepEqual(routeWaypoints[0], ['42', '12', '2026-07-05T15:00:06.900Z', '12', '0', '2', '1', '3', 'Forward', 'Off', 'Test Route', '0', '10', 'A', '52.11', '-1.21'])
  assert.deepEqual(routeWaypoints[1], ['42', '12', '2026-07-05T15:00:06.900Z', '12', '0', '2', '1', '3', 'Forward', 'Off', 'Test Route', '1', '11', 'B', '52.12', '-1.22'])

  const aisClassA = fs.readFileSync(path.join(typedDir, 'n2k_ais_class_a_position_129038_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(aisClassA, ['42', '13', '2026-07-05T15:00:06.910Z', '22', 'Scheduled Class A position report', 'Initial', '538012679', '132.30318', '28.2842716', 'Low', 'not in use', '54', '5.4897', '8.48', '229398', 'Channel B VDL reception', '5.4967', '0', 'Under way using engine', 'Not available', '1'])

  const aisClassB = fs.readFileSync(path.join(typedDir, 'n2k_ais_class_b_position_129039_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(aisClassB.slice(0, 10), ['42', '14', '2026-07-05T15:00:06.920Z', '22', 'Standard Class B position report', 'Initial', '235123456', '-1.1', '50.1', 'High'])

  const aisStaticA = fs.readFileSync(path.join(typedDir, 'n2k_ais_class_a_static_129794_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(aisStaticA.slice(0, 11), ['42', '15', '2026-07-05T15:00:06.930Z', '22', 'Static and voyage related data', 'Initial', '538012679', '9169316', 'V7B3189', 'GRAND CHOICE', 'Cargo ship'])

  const aisStaticBPartA = fs.readFileSync(path.join(typedDir, 'n2k_ais_class_b_static_a_129809_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(aisStaticBPartA, ['42', '16', '2026-07-05T15:00:06.940Z', '22', 'Static data report', 'Initial', '235123456', 'CLASS B BOAT', 'Channel A VDL reception', '2'])

  const aisStaticBPartB = fs.readFileSync(path.join(typedDir, 'n2k_ais_class_b_static_b_129810_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(aisStaticBPartB.slice(0, 10), ['42', '17', '2026-07-05T15:00:06.950Z', '22', 'Static data report', 'Initial', '235123456', 'Sailing', 'ABC123', 'MABC7'])

  const environment310 = fs.readFileSync(path.join(typedDir, 'n2k_environment_130310_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(environment310, ['42', '18', '2026-07-05T15:00:07.000Z', '4', '2', '291.15', '293.15', '101325'])

  const environment311 = fs.readFileSync(path.join(typedDir, 'n2k_environment_130311_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(environment311, ['42', '19', '2026-07-05T15:00:08.000Z', '4', '3', 'Sea Temperature', 'Inside', '292.15', '0.67', '101000'])

  const temperature312 = fs.readFileSync(path.join(typedDir, 'n2k_temperature_130312_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(temperature312, ['42', '20', '2026-07-05T15:00:09.000Z', '4', '4', '1', 'Sea Temperature', '289.15', '290.15'])

  const pressure314 = fs.readFileSync(path.join(typedDir, 'n2k_pressure_130314_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(pressure314, ['42', '21', '2026-07-05T15:00:10.000Z', '22', '5', '0', 'Atmospheric', '100900'])

  const temperature316 = fs.readFileSync(path.join(typedDir, 'n2k_temperature_ext_130316_stage_v2.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(temperature316, ['42', '22', '2026-07-05T15:00:11.000Z', '35', '6', '2', 'Sea Temperature', '288.15', '289.15'])
})

test('nested PGNs preserve list order and repeated identities without placeholder rows', () => {
  const input = [
    JSON.stringify({
      input: ['(1783263700.000000) can0 19FA040B#0011223344556677'],
      pgn: 129540,
      src: 11,
      fields: { SID: 1, 'Sats in View': 2, list: [
        { PRN: 7, SNR: 40 },
        { PRN: 7, SNR: 41 }
      ] }
    }),
    JSON.stringify({
      input: ['(1783263701.000000) can0 1DF9050C#0011223344556677'],
      pgn: 129285,
      src: 12,
      fields: { nItems: 2, list: [
        { 'WP ID': 5, 'WP Name': 'first' },
        { 'WP ID': 5, 'WP Name': 'second' }
      ] }
    }),
    JSON.stringify({
      input: ['(1783263702.000000) can0 19FA040B#0011223344556677'],
      pgn: 129540,
      src: 11,
      fields: { SID: 2, 'Sats in View': 0, list: [] }
    }),
    JSON.stringify({
      input: ['(1783263703.000000) can0 1DF9050C#0011223344556677'],
      pgn: 129285,
      src: 12,
      fields: { nItems: 0 }
    })
  ].join('\n') + '\n'

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'n2k-copy-nested-test-'))
  const typedDir = path.join(temp, 'typed')
  const { result } = runFixture(input, ['--typed-dir', typedDir])
  assert.equal(result.status, 0, result.stderr)

  const satellites = fs.readFileSync(path.join(typedDir, 'n2k_gnss_satellites_129540_stage_v2.tsv'), 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.deepEqual(satellites.map(row => [row[7], row[8], row[11]]), [['0', '7', '40'], ['1', '7', '41']])

  const waypoints = fs.readFileSync(path.join(typedDir, 'n2k_route_waypoint_129285_stage_v2.tsv'), 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.deepEqual(waypoints.map(row => [row[11], row[12], row[13]]), [['0', '5', 'first'], ['1', '5', 'second']])
})

test('skips malformed and non-decoded JSON rows', () => {
  const input = '{bad json}\n' + JSON.stringify({ fields: { A: 1 } }) + '\n'
  const { result } = runFixture(input)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stderr, /"framesWritten":0/)
  assert.match(result.stderr, /"skipped":2/)
})

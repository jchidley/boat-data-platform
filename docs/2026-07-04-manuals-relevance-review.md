# 2026-07-04 local boat manuals relevance review

Source folder inspected from WSL:

```text
C:\Users\jackc\OneDrive\Share for Delivery to USA\Manuals
/mnt/c/Users/jackc/OneDrive/Share for Delivery to USA/Manuals
```

Relevant PDFs were copied to `/tmp/boat-manuals-relevant` and converted with `pdftotext` to `/tmp/boat-manuals-text` for local searching. Do not run builds/indexers against `/mnt/c`; copy selected manuals to WSL first.

## Manuals checked

Most relevant to the boat data platform:

- `Lithium batteries setup.pdf`
- `1260 Lithium Install July 2023_Wiring Document.pdf`
- `10000015492_09manualChargeMasterPlusII_EN.pdf`
- `10000015714_19UserManualCombiMaster120Vseries.pdf`
- `10000016594_06_manualChargeMasterPlus1_EN.pdf`
- `10000011559_12_ManualEasyView5_EN.pdf`
- `MasterBus-USB_Interfa080916EN.pdf`
- `en-us-Zeus3S-IM_EN_988-12599-002_w.pdf`
- `b-and-g-zeus2-mfd-operator-manual[1].pdf`
- `Vesper_Marine_Cortex_Hub_Installation_Guide_English_DEC21_WEBv2.pdf`
- `Yanmar 3YM30AE manual.pdf` was present, but text extraction yielded almost no useful text; it likely needs OCR if engine details are needed later.

## Seawind lithium / alternator setup

`Lithium batteries setup.pdf` is directly relevant and confirms the expected architecture:

- House bank: `2 x Mastervolt Lithium 6000Wh MLi house batteries`, nominal `460 Ah` each, total `920 Ah` house capacity.
- Start batteries: `2 x 130 Ah AGM start batteries`.
- House charging alternators: `2 x Mastervolt Alpha Compact 14/120 high-output alternators`.
- Regulators: `2 x Mastervolt Alpha Pro III regulators` charging the lithium house bank.
- Engine/start alternators: `2 x Yanmar 120 Ah standard alternators` charging the AGM start batteries.
- A DC-DC charger can charge a start AGM from the lithium house bank in an emergency.
- Seawind states the Mastervolt alternators are connected to Mastervolt regulators which control output and prevent overcharging.
- Seawind describes the lithium BMS shutdown threshold as 20% physical SOC, while the displayed SOC is configured as usable capacity; displayed `0%` corresponds roughly to the BMS reserve threshold rather than truly empty.

Implications for this repo:

- The current `alpha-port` / `alpha-stbd` MasterBus devices are very likely the two Mastervolt Alpha Compact alternator/regulator paths for the house bank.
- Engine-running inference should use Alpha regulator/alternator signals (`senseVoltage`, optionally `fieldCurrent`) rather than battery bus voltage or alternator `.current` alone.
- There are also separate Yanmar alternators for start batteries; they may not appear as the MasterBus Alpha devices.

## Engine-state voltage threshold

The local Mastervolt manuals support replacing the old `> 5 V` proof threshold with a charging-voltage threshold.

`10000015492_09manualChargeMasterPlusII_EN.pdf` says for 12 V systems:

- AGM/Gel: bulk `14.4 V`, absorption `14.25 V`, float `13.80 V`.
- Flooded: bulk `14.4 V`, absorption `14.25 V`, float `13.25 V`.
- Lithium-ion: bulk `14.25 V`, absorption `14.25 V`, float `13.50 V`.
- The charger switches to float at `13.25 V` flooded, `13.8 V` gel/AGM, or `13.5 V` MLI at 25 °C.

`10000015714_19UserManualCombiMaster120Vseries.pdf` confirms similar values for CombiMaster 12 V charging specifications:

- Flooded float: `13.25 V`.
- GEL/AGM float: `13.80 V`.
- Li-ion/MLI float: `13.50 V`.
- Li-ion/MLI return-to-bulk voltage: `13.25 V`.
- Absorption: `14.25 V`.

`10000016594_06_manualChargeMasterPlus1_EN.pdf` confirms the same general ChargeMaster Plus values: absorption `14.25 V`; float `13.25 V` flooded, `13.8 V` gel/AGM, and `13.5 V` lithium-ion.

Implications for this repo:

- The `signalk-two-engine-state` default threshold of `13.25 V` is now supported by local manuals, not just web guidance.
- `13.25 V` is the lower 12 V charging/float threshold across the referenced Mastervolt charging profiles, and is a better minimum than `5 V` for proving the alternator/regulator is actually producing charge-level voltage.
- Current observed starboard sense voltage around `13.5 V` remains above threshold and therefore `started`.
- If physical tests show voltage sag/noise around the threshold, consider hysteresis, e.g. start `> 13.25 V`, stop `< 13.0 V`, but do not add this before observing real transitions.

## MasterBus topology and safety

`MasterBus-USB_Interfa080916EN.pdf` and `10000011559_12_ManualEasyView5_EN.pdf` confirm:

- MasterBus is a CAN-based, fully decentralized Mastervolt network.
- It is used for monitoring, control, and configuration of devices such as inverter, charger, generator, and batteries.
- Devices are chained using straight UTP/MasterBus cables.
- The network needs a terminating device at both ends.
- Do not make ring networks.
- Do not make T-connections.
- Do not connect non-MasterBus devices directly to MasterBus; use the proper interface.
- The MasterBus USB interface is a communication interface between a PC and the MasterBus network and can power up to three non-powering devices while the PC is on.
- EasyView 5 can monitor, configure, and operate all connected MasterBus devices, including alarms and event-based commands.

Implications for this repo:

- Keep `masterbus-signalk` read-only unless a separate safety review explicitly approves writes/events/control.
- Preserve MasterBus discovery/config snapshots; MasterBus state cannot be reconstructed from NMEA 2000 raw logs.
- If MasterBus devices disappear, check physical topology, terminators, power, and the USB interface before changing application code.
- Treat EasyView/MasterAdjust configuration as the authoritative human/operator configuration path; repo automation should observe, not alter, MasterBus settings.

## ChargeMaster / CombiMaster data that may be worth mapping later

The ChargeMaster Plus and CombiMaster manuals list MasterBus/CZone-visible monitoring fields and events including:

- Charger state: `Off`, `Bulk`, `Absorption`, `Float`, `Stopped`.
- Device state: `Charging`, `Stand-by`, `Alarm`, `Off`.
- AC present.
- AC input limit.
- DC output voltage/current per output.
- Battery temperature.
- MasterShunt / MLI battery mismatch alarms.
- Charger runtime / inverter runtime history.
- Events for bulk, absorption, float, failure, and stop charge.

Implications for this repo:

- Future MasterBus mapping could expose charger/inverter state and charger phase if useful for Grafana and logbook context.
- Do not use charger state alone for engine-running inference; it can indicate shore/generator charging, not necessarily an engine alternator.
- `Stop Charge` events for MLI batteries are control-path behaviour; do not automate them from this repo without explicit review.

## NMEA 2000 / B&G Zeus3S

`en-us-Zeus3S-IM_EN_988-12599-002_w.pdf` confirms:

- Zeus3S has an NMEA 2000 Micro-C port.
- The NMEA 2000 network is a powered backbone with drop cables.
- Backbone max length: `100 m`.
- Single drop max length: `6 m`; total drops max `78 m`.
- A terminator is required at each end of the backbone.
- The NMEA 2000 network needs its own `12 V` supply protected by a `3 A` fuse.
- Do not power NMEA 2000 from the same terminals as engine start batteries, autopilot computer, bow thruster, or other high-current devices.
- Zeus3S source selection matters: if multiple sources provide the same data, the preferred source can be auto-selected or manually selected.
- Zeus3S receives many PGNs relevant to our raw N2K archive, including `127488`, `127489`, `127493`, `127505`, `127506`, `127507`, `127508`, `127509`, navigation, GNSS, AIS, wind, depth, speed, and heading PGNs.

Implications for this repo:

- The raw N2K source-of-truth approach remains correct; Zeus3S is another display/consumer on the same network.
- Source conflicts in Signal K or on displays are expected in multi-source systems; prefer explicit source inspection rather than assuming one canonical source.
- If engine PGNs `127488`/`127489` are absent from our captures, the manual says Zeus can receive them, but does not prove Yanmar engines are actually gatewayed to N2K.

## Vesper Cortex AIS / NMEA 2000

`Vesper_Marine_Cortex_Hub_Installation_Guide_English_DEC21_WEBv2.pdf` confirms:

- Cortex shares AIS data with onboard devices over NMEA 2000, NMEA 0183, and WiFi.
- Cortex connects to NMEA 2000 using a drop cable and T connector.
- Device Instance and System Instance can be configured from the Cortex app or handset.
- Cortex has an NMEA 2000 status indicator: orange means not connected/not powered, green means connected/exchanging data, red means bus error.
- Cortex sends AIS/GNSS-related PGNs including `129025`, `129026`, `129029`, `129038`, `129039`, `129040`, `129041`, `129794`, `129798`, `129801`, `129802`, `129809`, `129810`, and wind `130306` translated from NMEA 0183.
- Cortex receives and translates a limited set of instrument/navigation PGNs to NMEA 0183/WiFi, including heading `127250`, STW `128259`, depth `128267`, log `128275`, route/navigation, wind `130306`, pressure and water temperature PGNs.

Implications for this repo:

- Cortex is a likely source for AIS/GNSS PGNs in raw N2K captures.
- Cortex is not shown as a source for engine or battery PGNs in the extracted PGN table.
- For AIS/GNSS source attribution, inspect Signal K source metadata and N2K source addresses before assuming data comes from Zeus or another device.

## Wiring document

`1260 Lithium Install July 2023_Wiring Document.pdf` text extraction mostly captured the DC distribution labels, including:

- `DISPLAY, RADAR, NAVIGATION` on a `10A` circuit.
- `AUTO PILOT` on a `30A` circuit.
- `VESPER CORTEX VHF` on a `10A` circuit.
- USB, fridges/freezer, pumps, fans, sat phone, security, camera circuits.

Implications for this repo:

- This supports treating Cortex and navigation electronics as separately powered loads; power cycling or troubleshooting one circuit may affect observed N2K/AIS availability.
- The extracted text is incomplete; use the PDF visually or OCR if exact circuit tracing is needed.

## Additional deeper findings from broader manual pass

A broader pass over all PDFs in the manual folder found several additional facts that can inform future dashboards, validation, and source attribution.

### Seawind 1260 owner manual: capacities and older electrical baseline

`SW1260 Owners Manual.pdf` appears to describe a more generic/older Seawind 1260 baseline than the later lithium-install document, so treat its electrical battery-capacity details as historical/generic when they conflict with the July 2023 lithium document. It is still useful for vessel capacities and system locations:

- Water tank capacity: `700 L` / `185 US gal`.
- Fuel tank capacity: two tanks, total `480 L` / `127 US gal`; each tank is about `240 L` / `64 US gal`; no fuel changeover facility.
- Holding tanks: two tanks, total `240 L` / `63 US gal`.
- Hot water tank: `40 L` / about `11 US gal`; heated by port engine heat exchanger or optional shore power. The manual says the port engine must run for at least about `30 min` to heat water, depending on ambient temperature.
- Electric bilge pumps are directly connected to house batteries and do not depend on the main house battery switch.
- The generic electrical section describes engine alternators and VSR charging for non-lithium setups, but the later lithium document supersedes this for the current boat's Mastervolt Alpha/MLI arrangement.

Plan implications:

- Add static vessel constants for dashboards/docs: fuel capacity `240 L` per hull/tank, water `700 L`, holding `120 L` per tank if later tank mapping appears.
- If Signal K has or later gains `tanks.fuel.*` / `tanks.freshWater.*` / `tanks.blackWater.*`, validate scaling against these capacities.
- The hot-water note gives a possible future logbook/electrical context: port engine runtime may correlate with hot-water availability, but do not automate any control from this.
- Bilge pump status would be valuable if a source becomes available; absence from current Signal K should be noted as a safety-monitoring gap, not assumed normal.

### Yanmar 3YM30AE engine manual: image-inspected facts

`Yanmar 3YM30AE manual.pdf` is copy-protected (`copy:no`), so `pdftotext` produced almost no useful content. Selected pages were rendered with `pdftoppm` and inspected as images.

Relevant image-inspected facts:

- Engine covered: `3YM30AE`.
- Type: vertical water-cooled 4-cycle diesel, 3 cylinders, natural aspiration.
- Displacement: `1.267 L`.
- Continuous power: `19.4 kW` / `26.4 hp metric` at `3101 min-1`.
- Fuel stop power: `21.3 kW` / `29.0 hp metric` at `3200 min-1`.
- Cooling: coolant cooling with heat exchanger.
- Starting motor: `DC 12 V`, `1.4 kW`.
- AC alternator: `12 V - 120 A`.
- Marine gear variants shown include `KM2P-1` and `SD-20`.

Plan implications:

- The Yanmar engine has its own `12 V 120 A` alternator, consistent with the Seawind lithium document's separate start-battery alternators. Do not confuse those with the Mastervolt Alpha Compact alternators on MasterBus.
- If NMEA 2000 engine PGNs ever appear, expect engine speed around the 0-3200 rpm range and two engine instances. But the manual itself does not prove a Yanmar-to-N2K gateway is installed.
- Future engine dashboards should not expect direct Yanmar electronic engine data unless raw N2K evidence shows PGNs `127488`/`127489` from an engine gateway.

### SD-20 saildrive manual

`SD 20 Yanmar Sail Drive.pdf` text extracted well enough to confirm it is maintenance/mechanical rather than data-platform oriented. It does not add NMEA/Signal K data sources. It may be useful for maintenance logs, not for live telemetry planning.

### NMEA 2000 display/source behaviour: Zeus manuals

The Zeus3S installation and operator manuals reinforce several data-platform points:

- The Zeus3S receives common NMEA 2000 engine/electrical/navigation PGNs, including engine `127488`/`127489`, fluid `127505`, DC detailed status `127506`, charger `127507`, battery `127508`, inverter `127509`, heading, rudder, speed, depth, GNSS, AIS, wind, and environmental PGNs.
- The Zeus3S transmits selected NMEA 2000 navigation/sensor PGNs, including time, heartbeat, heading/track control, vessel heading, magnetic variation, switch bank control, speed, depth, distance log, GNSS, route/navigation, wind, environmental parameters, direction data, and vessel speed components.
- Zeus source selection is explicit: when more than one source provides the same data, the user can auto-select or manually select preferred sources.

Plan implications:

- Treat N2K source attribution as important. For any duplicated Signal K path, inspect source labels/source addresses before deciding which is authoritative.
- The static PGN capability matrix should include whether a PGN is merely display-supported by Zeus versus actually observed on the raw bus.
- Be cautious about any Zeus-transmitted control/navigation PGNs (`127237`, `127502`, route/WP service). Our platform remains receive-only and should not transmit.

### Vesper Cortex: likely AIS/GNSS source, not engine/electrical source

The Cortex manuals confirm it is a Class-B SOTDMA AIS/VHF/GNSS device with NMEA 2000, NMEA 0183, and WiFi gateway functions.

Relevant points:

- Cortex shares AIS data over NMEA 2000, NMEA 0183, and WiFi.
- Device Instance and System Instance are configurable.
- It sends AIS/GNSS PGNs including position, COG/SOG, GNSS position, AIS Class A/B reports, AIS static data, safety messages, and related PGNs.
- It receives/translates selected instrument/navigation PGNs such as heading, STW, depth, log, route/navigation, wind, pressure, and water temperature.
- The extracted PGN table does not indicate Cortex as an engine/electrical source.

Plan implications:

- Cortex is a likely source for AIS/GNSS paths in Signal K and raw N2K.
- Do not attribute engine/battery PGNs to Cortex unless raw source metadata proves it.
- If AIS/GNSS gaps occur, Cortex NMEA 2000 status LEDs and instance settings are relevant troubleshooting points.

### Airmar DST800/DST810 transducer manual

`transducer manual.pdf` identifies the transducer family as Airmar `DST800` / `DST810` Triducer multisensor.

Relevant points:

- Provides depth, speed-through-water, water temperature; DST810 also supports attitude and Bluetooth/CAST app data viewing.
- Installation guidance emphasizes smooth water flow, continuous immersion, and avoidance of turbulence/bubbles.
- Sensor cable should be separated from other electrical wiring to reduce interference.
- Anti-fouling and paddlewheel maintenance affect data quality.

Plan implications:

- Depth/STW/water-temperature dropouts or noise may be physical fouling/turbulence, not software decode failure.
- Grafana freshness panels should separate data freshness from data quality; a fresh but implausible STW/depth value may need separate QA rules.
- If DST810 is installed, local Bluetooth/CAST inspection could help diagnose transducer-specific issues, but this is outside the current Pi data path.

### High-load and auxiliary electrical consumers

The manuals identify several loads that can explain battery/inverter/charger behaviour but are not necessarily visible as individual Signal K paths.

- `Schenker Zen 50 Owners Manual.pdf`:
  - Watermaker power: `12 VDC +/- 15%` or `24 VDC +/- 15%` depending model.
  - Average electrical consumption: about `250 W` continuous.
  - Nominal production: `50 L/h +/- 20%` at seawater 25 °C / salinity 35,000 ppm.
  - Requires `32 A` breaker on 12 V systems or `16 A` on 24 V systems.
  - Alarms include unit stalled, underpressure, overpressure, low battery, and pressure-transducer/control failure.
- `Fridge Isotherm CR360.pdf`:
  - 12/24 V DC refrigerator/freezer with low-voltage compressor protection.
  - 12 V low-voltage shut-down shown as `9.6 V` or `10.4 V` depending bridge setting; restart/minimum operating `10.9 V` or `11.7 V`.
  - Recommended refrigerator temperature around `5-6 °C`.
- `Air Conditioning UFlex Velair i16 VSD SMART.pdf`:
  - Self-contained marine air-conditioning/heating unit, `i10/i16 VSD SMART` family.
  - Uses `230 V AC / 1 ph / 50-60 Hz` line supply in the extracted wiring section.
  - Has integrated WiFi module and active alarms on its display, but no NMEA/Signal K integration was found in the extracted text.
- `Clothes Washer-Avanti-ctw84x0wis.pdf`:
  - Requires standard `115/120 V AC 60 Hz`; circuit/fuse guidance mentions `15 A` and at least `10 A` electrical capacity.
- `Harken 46 Electric Winch.pdf`:
  - Electric winch motor kit is `0.7 kW` for 12/24 V versions.
  - HCP model shown as `HCP1717`, `80 A` rating.
- `Maxwell AutoAnchor 560.pdf`:
  - AutoAnchor controller supply `12/24 V DC`, current consumption `70 mA`, output current draw max `4 A`.
  - Windlass operation minimum start voltage: `10 V` for 12 V systems, `20 V` for 24 V; minimum continue voltage `7 V` / `14 V`.

Plan implications:

- Short high-current DC loads (winches, windlass) and AC loads (aircon, washer via inverter/shore/generator) can explain transient battery current and voltage behaviour. Do not use house battery current alone for engine state.
- Future Grafana electrical dashboards should annotate or infer likely load classes rather than assuming all current swings are charging events.
- If individual load states are not available on N2K/MasterBus, consider manual/logbook annotations before trying to infer too much from aggregate current.
- Watermaker and refrigeration low-voltage alarms are good candidates for future manual observation/logging, but not current automatic ingestion unless interfaces are found.

### Manuals with little direct data-platform relevance

The following manuals are useful operationally but did not materially affect the data-platform plan in the extracted text:

- EPIRB manual.
- Parasailor/shark drogue/beachmaster/sail-plan docs.
- Oil extractor and Racor manuals.
- Webasto MultiControl operating instructions: useful for heater error codes/timers, but no NMEA/Signal K integration was found in extracted text.

## Direct plan adjustments from manuals

1. Keep `signalk-two-engine-state` threshold at `13.25 V` unless physical transition tests prove a need for hysteresis.
2. Continue using `senseVoltage` as the primary engine-running signal and `fieldCurrent` as corroborating evidence.
3. Do not infer engine-running from house battery voltage or charger state, because Mastervolt chargers/solar/inverter/shore power can also affect those values.
4. Keep MasterBus integration receive-only/read-only in repo automation.
5. Add future optional MasterBus mapping candidates for charger/inverter state, charge phase, AC present, charger runtime, inverter runtime, and alarms.
6. Add future optional dashboard constants for fuel/water/holding capacities from the Seawind owner manual, validating against any actual tank sender paths before presentation.
7. Treat Cortex as likely AIS/GNSS source and Airmar DST as likely depth/STW/water-temperature source; verify with raw N2K source addresses and Signal K sources.
8. Track high-load devices as context for electrical analysis: watermaker (`~250 W`), winches (`0.7 kW`, high-current), windlass, aircon (`230 V AC`), washer (`115/120 V AC`).
9. Keep the static PGN capability matrix task: manuals confirm devices can receive/display common engine/battery PGNs, but local raw/canboat inspection is still required to know what is actually present and decoded.

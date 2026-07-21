# 2026-07-04 static PGN capability matrix

Purpose: answer the next planning gate without running live import/backfill work on `pi5nvme`: for each high-value or suspicious PGN, separate manual/device support, local canboat decode support, local `n2k-signalk` mapping support, and whether existing boat inventory says the raw bus contains it.

This is a static source-inspection document. It uses local manuals/docs, local unpacked source, and the existing human-readable discovery inventory only. It does **not** start importers, run analyzer backfills, query broad database aggregates, or write proprietary parsers.

## Sources inspected

- Boat/device facts: [`2026-07-04-manuals-relevance-review.md`](2026-07-04-manuals-relevance-review.md)
- Existing observed-bus summary: [`2026-07-03-boat-discovery-and-decoder-inventory.md`](2026-07-03-boat-discovery-and-decoder-inventory.md)
- canboat PGN database: `/home/jack/src/boat-study/signalk/unpacked/canboat-pgns-6.0.2/canboat.json`
- n2k-signalk mappings: `/home/jack/src/boat-study/signalk/unpacked/signalk-n2k-signalk-4.6.0/pgns/`
- canboatjs package: `/home/jack/src/boat-study/signalk/unpacked/canboat-canboatjs-3.20.0`

Inspection commands used included targeted `jq` over `canboat.json`, checking for `pgns/<PGN>.js|ts` in `n2k-signalk`, and targeted reads of mapping files for representative Signal K paths.

## Matrix legend

- **Manual/device support**: a device manual or device plan says a device can send/receive/display the PGN. This does not prove this boat transmits it.
- **canboat**: local canboat PGN definition status. `complete` means canboat marks the PGN complete; `partial` means defined but `Complete=false`; `absent` means not found in local canboat definitions.
- **n2k-signalk**: local mapping file exists in `signalk-n2k-signalk-4.6.0/pgns/`.
- **Observed here**: existing discovery docs say the boat bus has shown this PGN. It is intentionally not a fresh backfill/import result.
- **Likely source**: current hypothesis only; source-address inventory is the next task.

## Priority/suspicious PGNs

| PGN | Meaning / local canboat description | Manual/device support | canboat | n2k-signalk | Observed here | Likely source | Recommended action |
|---:|---|---|---|---:|---:|---|---|
| 65313 | Navico proprietary, not in local canboat | B&G/Navico traffic expected from Zeus/network | absent | no | yes | B&G/Zeus/Navico | Low priority until source counts/frequency show it carries a missing value. Preserve raw only. |
| 65317 | Navico proprietary 2, not in local canboat | B&G/Navico traffic expected from Zeus/network | absent | no | yes | B&G/Zeus/Navico | Low priority; do not write parser yet. |
| 65350 | `Simnet: Magnetic Field` | Simnet/Navico compass/magnetic traffic plausible | partial | no | yes | B&G/Navico/Simnet heading sensor or autopilot network | Keep as raw/decoded canboat partial. Source-attribution may show if it complements `127250` heading. |
| 130821 | `Navico: ASCII Data`; also Furuno variant exists | B&G/Navico proprietary traffic expected | partial | no | yes | B&G/Zeus/Navico | Highest proprietary candidate. Existing inventory says analyzerjs exposes comma-separated ASCII payload. Inspect a small bounded sample only when a concrete missing display value is suspected. |
| 130822 | `Navico: Unknown 1` | B&G/Navico/BEP traffic expected | partial | no | yes | B&G/Navico/BEP/CZone | Preserve raw. Low priority unless frequent and correlated with missing switching/config state. |
| 130824 | `B&G: key-value data`; also Maretron annunciator variant exists | B&G/Navico proprietary traffic expected; web/local plan flags it as promising | partial | no | yes, earlier samples | B&G/Navico/SimNet | Promising but still no parser project yet. First source-count and bounded sample if a needed B&G key/value is missing from standard Signal K. |
| 130860 | `Simnet: AP Unknown 4` | Autopilot/control traffic plausible from Zeus/Navico network | partial | no | yes | B&G/Simrad/Navico autopilot | Observe only. Do not transmit/control. Investigate only for read-only autopilot context use case. |

## Engine and electrical/tank PGNs

| PGN | Meaning / local canboat description | Manual/device support | canboat | n2k-signalk | Observed here | Likely source | Recommended action |
|---:|---|---|---|---:|---:|---|---|
| 127488 | Engine Parameters, Rapid Update | Zeus can receive/display; Yanmar manual does **not** prove gateway installed | complete | yes | no / not clear | Yanmar gateway if one exists | Do not build RPM dashboards until raw source inventory shows it. Mapping would emit `propulsion.<engine>.revolutions`, trim, boost pressure. |
| 127489 | Engine Parameters, Dynamic | Zeus can receive/display; Yanmar manual does **not** prove gateway installed | complete | yes | no / not clear | Yanmar gateway if one exists | Do not rely on direct engine data yet. Mapping would emit temperature, alternator voltage, fuel rate, oil/coolant pressure, engine load/torque, `runTime`, and notifications. |
| 127505 | Fluid Level | Zeus can receive/display; boat manuals provide static tank capacities | complete | yes | no / not clear | Tank sender/gateway if installed | If later observed, validate tank instance/capacity against manual constants before presentation dashboards. |
| 127506 | DC Detailed Status | Zeus can receive/display | complete | yes | no / not clear | N2K battery monitor if installed; MasterBus is current electrical source instead | Current house electrical path remains MasterBus. If observed later, compare with MasterBus before using. |
| 127507 | Charger Status | Zeus can receive/display | complete | yes | no / not clear | N2K charger if installed; MasterBus charger is current known path | Prefer MasterBus CombiMaster/charger mapping for now. Avoid using charger state for engine-running inference. |
| 127508 | Battery Status | Zeus can receive/display | complete | yes | no / not clear | N2K battery monitor if installed; MasterBus is current known path | If observed, source-attribute and compare against MasterBus `electrical.batteries.*`. |
| 127509 | Inverter Status | Zeus can receive/display | complete | yes | no / not clear | N2K inverter if installed; MasterBus CombiMaster currently known | Prefer MasterBus until N2K source is proven. |

## Airmar / instrument PGNs

| PGN | Meaning / local canboat description | Manual/device support | canboat | n2k-signalk | Observed here | Likely source | Recommended action |
|---:|---|---|---|---:|---:|---|---|
| 128259 | Speed, Water Referenced | Airmar DST800/DST810; Zeus/Cortex can consume | complete | yes | yes | Airmar DST transducer likely | Source-attribution next. Mapping emits `navigation.speedThroughWater` and reference type; add plausibility/fouling checks later. |
| 128267 | Water Depth | Airmar DST800/DST810; Zeus/Cortex can consume | complete | yes | yes | Airmar DST transducer likely | Source-attribution next. Mapping emits depth below transducer/surface/keel depending offset. |
| 128275 | Distance Log | Airmar DST/Cortex/Zeus support context | complete | yes | yes | Airmar DST or nav display | Source-attribution next. Mapping emits `navigation.log` and `navigation.trip.log`. |
| 130310 | Environmental Parameters, obsolete | Zeus/Cortex environmental support; older devices may send | complete | yes | yes | Airmar/instrument network | Keep standard mapping; prefer source attribution and quality checks. |
| 130311 | Environmental Parameters | Zeus/Cortex environmental support | complete | yes | yes | Airmar/instrument network | Keep standard mapping; source attribution needed. |
| 130312 | Temperature | DST water temperature and other environmental sensors | complete | yes | no / not in existing observed list | Airmar DST if configured | If absent but water temp is present via `130316`/`130310`/`130311`, no action. Mapping uses Signal K temperature source table. |
| 130316 | Temperature Extended Range | DST810/material flags temperature support | partial | yes | yes | Airmar DST likely | Already useful despite canboat `Complete=false`. Mapping uses Signal K temperature source table, commonly water temperature. |
| 130306 | Wind Data | B&G/Zeus/Cortex support; wind instrument likely | complete | yes | yes | Wind sensor or translated source | Source-attribution next. Mapping emits apparent/true wind paths depending reference. |

## Vesper Cortex / AIS / GNSS PGNs

| PGN | Meaning / local canboat description | Manual/device support | canboat | n2k-signalk | Observed here | Likely source | Recommended action |
|---:|---|---|---|---:|---:|---|---|
| 129025 | Position, Rapid Update | Cortex sends; Zeus can receive/display | complete | yes | yes | Cortex likely, possibly Zeus/GNSS | Source-attribution next. Mapping emits `navigation.position`. |
| 129026 | COG & SOG, Rapid Update | Cortex sends; Zeus can receive/display | complete | yes | yes | Cortex likely, possibly Zeus/GNSS | Source-attribution next. Mapping emits SOG and COG true/magnetic. |
| 129029 | GNSS Position Data | Cortex sends; Zeus can receive/display | complete | yes | yes | Cortex likely | Source-attribution next. |
| 129038 | AIS Class A Position Report | Cortex sends AIS over N2K | complete | yes | yes | Cortex likely | Confirm source address/product info. |
| 129039 | AIS Class B Position Report | Cortex sends AIS over N2K | complete | yes | yes | Cortex likely | Confirm source address/product info. |
| 129040 | AIS Class B Extended Position Report | Cortex/Zeus AIS support | partial | yes | no / not in existing observed list | Cortex if present | No action unless observed gaps require it. |
| 129041 | AIS Aids to Navigation Report | Cortex AIS support | complete | yes | no / not in existing observed list | Cortex if nearby AtoN exists | Normal to be absent unless received from AIS environment. |
| 129794 | AIS Class A Static/Voyage Data | Cortex sends AIS over N2K | complete | yes | yes | Cortex likely | Confirm source address/product info. |
| 129798 | AIS SAR Aircraft Position Report | Cortex AIS support | partial | yes | no / not in existing observed list | Cortex if SAR aircraft received | No issue if absent. |
| 129801 | AIS Addressed Safety Related Message | Cortex AIS safety message support | partial | no | no / not in existing observed list | Cortex if message received | canboat partial but no Signal K mapping here; preserve raw if observed. |
| 129802 | AIS Safety Related Broadcast Message | Cortex AIS safety message support | partial | no | no / not in existing observed list | Cortex if message received | canboat partial but no Signal K mapping here; preserve raw if observed. |
| 129809 | AIS Class B static data part A | Cortex sends AIS over N2K | complete | yes | yes | Cortex likely | Confirm source address/product info. |
| 129810 | AIS Class B static data part B | Cortex sends AIS over N2K | complete | yes | yes | Cortex likely | Confirm source address/product info. |

## Follow-up review note

The later redesign review [`postgresql-storage-plan.md`](postgresql-storage-plan.md) adds implementation-specific gaps: current typed SQL converter coverage is only the first navigation/depth/wind slice; observed PGNs such as `127245`, `127251`, `127257`, `127258`, `127237`, `127501`, `129284`, `129285`, `129539`, `129540`, `130314`, `130316`, and AIS PGNs still need schema/converter work; and proprietary parser work should first compare local canboat `6.0.2` with current canboat and OpenCPN TwoCan findings.

## Conclusions

1. Standard navigation, AIS, wind, depth/STW/log, environmental, tank, engine, and N2K electrical PGNs are generally well covered by local canboat and `n2k-signalk`.
2. The boat already shows strong standard coverage for GNSS/AIS, heading, wind, depth/STW/log, and water/environmental data.
3. Existing discovery still does **not** clearly show direct Yanmar engine PGNs (`127488`/`127489`), N2K electrical PGNs (`127506`-`127509`), or tank PGN `127505`; dashboards should not assume those exist.
4. B&G/Navico proprietary PGNs are genuinely present but mostly partial/no-mapping. `130821` and `130824` are the only proprietary candidates worth bounded follow-up before any parser work.
5. `65313` and `65317` are observed but absent from local canboat definitions, so they should remain raw-only unless a specific missing-value use case appears.
6. The next useful step is a source-attribution inventory: PGN/source-address/product-info and current Signal K `$source` labels, not deeper decoding.

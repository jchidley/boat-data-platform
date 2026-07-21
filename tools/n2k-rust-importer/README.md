# Direct Rust N2K importer

This experimental offline/staging converter embeds `canboat-core` at pinned revision `d0f7f24a41b1274f63b71f08703539554523858f` (embedded CANboat schema `7.1.0`). It does not replace the live Signal K/canboatjs path.

It reads edge candump text directly, reassembles fast packets, decodes in SI units and emits the same TSV contracts consumed by the PostgreSQL COPY wrapper. `message_index` is the one-based source candump line where a message begins, including for fast packets; it is not the decoder output sequence number.

Current direct typed coverage is deliberately incremental:

```text
127245 rudder
127250 heading
128259 water speed
128267 water depth
129025 rapid position
129026 COG/SOG
130306 wind
```

All decoded messages still contribute to disposable frame staging and file/source/PGN summaries. Unsupported typed PGNs remain available through the canboatjs comparison path until ported and validated.

Build and test:

```bash
npm run build:n2k-rust
npm run test:n2k-rust
```

Use through the bounded wrapper:

```bash
node scripts/import-n2k-v2-copy.mjs \
  --decoder rust \
  --raw-file sample.candump.log.gz \
  --sample-lines 10000 \
  --research-mode none \
  --dry-run --keep-work
```

The bounded parity, malformed/incomplete-packet, timestamp and staging delete/rebuild gates are complete for these seven PGNs. Use remains offline/staging-only and bounded; parity-gate every additional PGN before inclusion. Do not run a broad import or conversion on live `pi5nvme`.

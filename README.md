# boat-data-platform

Boat NMEA 2000 gateway, logging, Signal K, TimescaleDB/Grafana, and analysis platform.

## Current Status

This is an experimental boat data platform.

Current target:

```text
picanm  = raw NMEA 2000 acquisition edge
pi5nvme = Signal K, MasterBus, TimescaleDB/Postgres, Grafana, import, analysis
```

Preserve source material first:

- raw NMEA 2000 candump logs for N2K;
- MasterBus discovery/config snapshots for Mastervolt/MasterBus;
- repo docs/scripts for rebuild.

Treat Signal K state, TimescaleDB rows, inventories, summaries, and dashboards as derived/rebuildable while the system is experimental.

Start here:

- [documentation map](docs/README.md)
- [LLM implementation brief](docs/llm-implementation-brief.md)
- [platform plan](docs/plan.md)
- [edge/backend migration plan](docs/2026-07-03-edge-backend-migration-plan.md)
- [rebuild runbook](docs/rebuild-from-source-material.md)
- [boat discovery and decoder inventory](docs/2026-07-03-boat-discovery-and-decoder-inventory.md)

## About This Code

Almost all of this code is AI/LLM-generated. It's best used as a source of
inspiration for your own AI/LLM efforts rather than as a traditional library.

**This is personal alpha software.** All my GitHub projects should be considered
experimental. If you want to use them:

- **Pin to a specific commit** — don't track `main`, it changes without warning
- **Use AI/LLM to adapt** — without AI assistance, these projects are hard to use
- **Treat as inspiration** — build your own version rather than depending on mine

**Suggestions welcome** — If you have ideas for improvements or changes, I'd be
delighted to read them and use them as inspiration for my own efforts.

**Why not a library?** These days it's often quicker to use AI/LLM to build your
own than to integrate traditional libraries. My use of AI/LLM is inspired by
these people and posts:

- [Simon Willison's Weblog](https://simonwillison.net/) — Essential reading on
  LLMs, prompt engineering, and building with AI
- [CLI over MCP](https://lucumr.pocoo.org/2025/8/18/code-mcps/) — Armin Ronacher
  on why command-line tools are better integration points than custom protocols
- [Build It Yourself](https://lucumr.pocoo.org/2025/12/22/a-year-of-vibes/) —
  Armin Ronacher: "With our newfound power from agentic coding tools, you can
  build much of this yourself..."
- [Shipping at Inference Speed](https://steipete.me/posts/2025/shipping-at-inference-speed) —
  Peter Steinberger on the new workflow of building with AI assistance
- [Year in Review 2025](https://mariozechner.at/posts/2025-12-22-year-in-review-2025/) —
  Mario Zechner on AI-assisted development

**What I use:** Currently Anthropic's Claude Opus, evaluating OpenAI's GPT Codex
as an alternative.

## License

This project is dual-licensed under the terms of both the MIT license and the
Apache License (Version 2.0).

See [LICENSE-APACHE](LICENSE-APACHE) and [LICENSE-MIT](LICENSE-MIT) for details.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this project by you, as defined in the Apache-2.0 license,
shall be dual licensed as above, without any additional terms or conditions.

# SeeUsage

A lightweight macOS menu bar app and CLI for tracking AI coding quotas across Codex profiles, Antigravity, and Claude Code.

This is [fabinho5/SeeUsage](https://github.com/fabinho5/SeeUsage), a fork of [tiagoc211/SeeUsage](https://github.com/tiagoc211/SeeUsage).

<p align="center">
  <img src="./assets/seeusage-demo.gif" alt="SeeUsage demo" width="850">
</p>

## What is SeeUsage?

SeeUsage monitors your remaining AI coding allowances across local CLI accounts in a single, glanceable interface. It tracks 5-hour session limits and 7-day weekly quotas for Codex (including multiple isolated profiles) and Antigravity, with optional Claude Code usage sync.

## Features

- **Codex multi-profile tracking**: Simultaneously queries quotas across `~/.codex` and `~/.codex-profiles/*` without switching active accounts or reading credentials.
- **Antigravity quota monitoring**: Reads active `agy` rate limits across model families routed via Antigravity (Gemini, Claude & GPT models included in your Antigravity plan, distinct from direct Anthropic/Claude provider accounts).
- **Claude Code usage (optional)**: Enable usage sync in Settings → Providers to show Claude Code's 5-hour and weekly subscription quotas. SeeUsage reads Claude Code's local status-line data and preserves an existing custom status line.
- **Customizable menu bar**: Choose Lowest Quota, Dual Quotas, Mini Gauge, Icon Only, Stacked Bars, Stacked Percentages, or Account Percentages. In **Settings → General → Menu Bar**, the three account styles let you select accounts/providers, show each account or group by provider, and choose session, weekly, or lowest quota. With one selected account or provider, Stacked Bars shows the 5-hour session on top and the weekly quota below. Compact indicators follow your account order; hover to identify each reading.
- **Interactive watch dashboard (`seeusage watch`)**: Real-time terminal TUI with second-by-second countdowns to quota resets and theme switching.
- **Floating percentage bar**: Enable Settings → General → Appearance → Show floating bar for a draggable bar with per-profile quotas and no progress bars. Choose horizontal or vertical orientation, 5-hour/weekly/both quotas, and which providers or individual Codex profiles appear, in Settings or the bar’s right-click menu. Hiding a provider preserves its profile selections. Selected profiles remain visible with “—” when quota data is unavailable. The horizontal bar groups each profile name above its percentages and only scrolls when the screen cannot fit the content. Its position and preferences are saved; pin and hide actions are available in the right-click menu. The bar uses native, untinted Liquid Glass on macOS 26+, with frosted materials on older versions. A detailed HUD remains available through the CLI.
- **Banked Codex resets**: See available reset credits in the popover and confirm before activating one; the CLI can also list and consume credits.
- **Quota Analytics & Usage History**: Lightweight local history in `~/.config/seeusage/history.json`, with terminal summaries and CSV/JSON export for consumption and reset records.
- **Quota planning hints and markers**: The popover compares remaining quota with the allowance for the window's time left. For example, 97% left with 4h 19m until a 5-hour reset is about 11 percentage points in reserve. Green/red markers show that time-based budget on the bar; reserve means ahead of budget, deficit means behind. Deficit messages estimate time until exhaustion from average consumption since the current window began. Weekly hints also show windows until reset and estimated session capacity, with fractional counts once at least three complete, well-observed sessions establish their typical weekly cost. Pacing and window counts work immediately from fresh quota/reset data; session capacity learns separately per account and model scope. Tooltips retain the longer observed-history forecast, which needs 30 minutes for short windows or three days for weekly quotas. Estimates exclude stale/error data and can change with your usage.
- **Codex quota order**: The main Session and Weekly quotas appear together, followed by the separate GPT reserve pool. Raw quota IDs, scopes, and account data stay intact.
- **Account display controls**: Click an account header to collapse or expand its quota rows. Collapsed accounts retain a short quota summary. Use the header's `…` menu → Change display name to set a visual alias, or Use original name to restore it. Display names and collapsed sections survive restarts. Aliases appear in the popover, floating bar/HUD, profile choices, and activity details without changing account names, profile folders, authentication, or usage history.
- **Automatic refresh and shortcut**: Opening the menu bar popover immediately refreshes usage. Press **Command-R** in the popover, Settings, or another active SeeUsage window to refresh manually. Requests share the same refresh queue; cached quotas stay visible while new readings load.
- **UI profiles**: Fresh installations use Compact by default. Choose Compact or Classic in Settings → General → Appearance → UI profile. Compact keeps the current smaller text, tighter spacing, and inline hints that wrap when needed. Classic restores the original popover dimensions, larger bars, and reset lines below each bar, adding the same planning hints underneath. Both profiles share account display names, collapsed sections, history, notifications, and all other features. The selection persists and applies immediately; accent colors and floating bar settings remain independent.
- **Native system notifications**: Custom alerts when any quota drops below a configurable threshold and when limits reset back to 100%.
- **Fast shell prompt integration**: Instant cached one-liner (`seeusage --mini --cached`) for Starship, Zsh, and tmux prompts, plus JSON output (`--json`).
- **Local and private**: Runs entirely on your machine. Never stores, reads, or transmits tokens or authentication secrets.

## Installation

Clone the repository and run the installation script:

```bash
git clone https://github.com/fabinho5/SeeUsage.git
cd SeeUsage
./scripts/install.sh
```

This compiles the release binary, installs `SeeUsage.app` into `/Applications` (or `~/Applications` if the system folder is not writable), registers it with macOS, and links the `seeusage` CLI command to `~/.local/bin/seeusage`.

To start the menu bar app:

```bash
open -a SeeUsage
```

## Requirements

- macOS 14.0 (Sonoma) or newer
- macOS 26 SDK or newer for source builds (Xcode 26 or its Command Line Tools); the app still supports macOS 14+
- [Codex CLI](https://github.com/openai/codex) (`codex`) installed and authenticated (optional, for Codex tracking)
- [Antigravity CLI](https://github.com/google/antigravity) (`agy`) installed and authenticated (optional, for Antigravity tracking)

## CLI Usage

```bash
seeusage                     # Display formatted quota table for all accounts
seeusage watch               # Live interactive TUI with real-time countdown to reset
seeusage settings            # Open macOS preferences window
seeusage themes              # List available terminal themes
seeusage theme ocean         # Apply a terminal theme (e.g. emerald, ocean, tokyo-night)
seeusage mode stackedBars    # Compact bars for selected accounts; run `seeusage mode` for all styles
seeusage notify test         # Send an instant test notification
seeusage notify 15           # Set low-quota notification threshold to 15%
seeusage hud toggle          # Toggle floating desktop HUD widget on/off
seeusage hud compact         # Switch floating HUD to minimal compact pill layout
seeusage analytics           # View 7-day consumption summary, peak hours, and profile share
seeusage analytics csv       # Export recorded quota history to CSV
seeusage analytics json      # Export recorded quota history to JSON
seeusage --mini --cached     # Fast one-liner for shell prompts (reads local cache)
seeusage --json              # Output quota data as JSON
seeusage --export <profile>  # Print export CODEX_HOME=... command for shell switching
```

## How It Works

SeeUsage communicates with official CLI tools already authenticated on your system:

- **Codex**: Spawns an isolated `codex app-server --stdio` process for each configured profile path and requests rate limits via JSON-RPC (`account/rateLimits/read`). It never accesses `auth.json` directly.
- **Antigravity**: Runs `agy -p "/usage" --output-format text` to read active quota metrics and reset timestamps without consuming inference tokens.
- **Caching**: Aggregated metrics are stored in `~/.config/seeusage/cache.json` for zero-latency prompt queries and instant popover rendering.
- **History**: Retains up to 20,000 snapshots so frequent polling can collect enough history for weekly forecasts. Session estimates use the latest 14 days. Stored history dates use numeric Unix timestamps to preserve sampling precision; existing ISO 8601 history remains readable, and CSV/JSON exports continue to use ISO 8601 dates.

## Development

```bash
# Build debug executable
swift build

# Run the test suite
swift test

# Run the CLI directly
swift run SeeUsage

# Run the interactive watch dashboard
swift run SeeUsage watch

# Package the release macOS application bundle (dist/build.noindex/SeeUsage.app)
./scripts/build_app.sh
```

## Project Structure

```text
Sources/
  SeeUsage/
    SeeUsageApp.swift         # Menu bar status item, popover lifecycle, and entry point
    Views.swift               # SwiftUI menu bar popover and preferences window
    UsageStore.swift          # Quota polling, aggregation, and caching
    CodexClient.swift         # JSON-RPC client for codex app-server
    AntigravityClient.swift   # Parser for agy usage output
    CLIHandler.swift          # Terminal output, shell integration, and subcommands
    WatchDashboard.swift      # Interactive terminal TUI dashboard (seeusage watch)
    NotificationManager.swift # Threshold-based notifications and reset alerts
    Theme.swift               # Color palettes for UI and terminal rendering
scripts/
  build_app.sh                # Compiles and bundles dist/build.noindex/SeeUsage.app
  install.sh                  # Installs to /Applications (fallback ~/Applications) and ~/.local/bin
assets/                       # Demo media and screen recordings
```

## Contributing

Contributions, bug reports, and feature suggestions are welcome in [this fork’s issues](https://github.com/fabinho5/SeeUsage/issues) and [pull requests](https://github.com/fabinho5/SeeUsage/pulls).

## License

This repository does not currently contain a license file. See [Issues](https://github.com/fabinho5/SeeUsage/issues) to inquire about licensing.

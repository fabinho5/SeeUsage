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
- **Optional app updates**: DMGs built from version 1.1.1 include [Sparkle](https://sparkle-project.org). Settings → General → App updates offers **Check for updates** and an automatic-check toggle. Checks run at launch and hourly while the app is running; users can install, postpone, or skip a release. Installation requires their choice and relaunches the app. Preferences, aliases, profiles, and history remain outside the app bundle and survive updates. Software update checks are separate from quota refreshes.
- **UI profiles**: Fresh installations use Compact by default. Choose Compact or Classic in Settings → General → Appearance → UI profile. Compact keeps the current smaller text, tighter spacing, and inline hints that wrap when needed. Classic restores the original popover dimensions, larger bars, and reset lines below each bar, adding the same planning hints underneath. Both profiles share account display names, collapsed sections, history, notifications, and all other features. The selection persists and applies immediately; accent colors and floating bar settings remain independent.
- **Native system notifications**: Custom alerts when any quota drops below a configurable threshold and when limits reset back to 100%.
- **Fast shell prompt integration**: Instant cached one-liner (`seeusage --mini --cached`) for Starship, Zsh, and tmux prompts, plus JSON output (`--json`).
- **Local and private**: Runs entirely on your machine. Never stores, reads, or transmits tokens or authentication secrets.

## Installation

### Packaged app (DMG)

Download the universal DMG for Apple Silicon and Intel Macs from [this fork's latest release](https://github.com/fabinho5/SeeUsage/releases/latest). Open the DMG, drag **SeeUsage.app** into **Applications**, then open it. Quit an existing SeeUsage instance before replacing it, and eject the DMG after copying. You can also install into `~/Applications`.

The packaged app needs macOS 14 or newer, with no Swift compiler, Xcode, or Conda required. Provider CLIs still need to be installed and authenticated for their quotas to appear. Fresh installations use the Compact UI profile.

Users of 1.1.0 or an original source installation must install an updater-enabled DMG once. After that, new stable releases can be installed inside the app. A network connection is required for update checks, which contact GitHub; no provider credentials or system profiling data are sent. Checks can be disabled in Settings. Before a feed is published, manual checks show “You’re up to date” or “No updates have been published yet” based on GitHub's latest stable release. A newer release without a feed offers a manual release link. Network/server failures show a retryable status, and signature errors remain errors. These checks never install an unsigned release; missing feeds and network errors leave the installed app unchanged.

To use the optional terminal command, link the installed executable (adjust the app path if you installed into `~/Applications`):

```bash
mkdir -p "$HOME/.local/bin"
ln -sf "/Applications/SeeUsage.app/Contents/MacOS/SeeUsage" "$HOME/.local/bin/seeusage"
export PATH="$HOME/.local/bin:$PATH"
```

Add the `export` line to your shell configuration to keep the command on your PATH.

Local builds are ad-hoc signed unless you supply a Developer ID identity. For a trusted download blocked by macOS, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). Public Developer ID releases should be signed and notarized as described below.

### Build and install from source

Clone the repository and run the installation script:

```bash
git clone https://github.com/fabinho5/SeeUsage.git
cd SeeUsage
./scripts/install.sh
```

This compiles the release binary, installs `SeeUsage.app` into `/Applications` (or `~/Applications` if the system folder is not writable), registers it with macOS, and links the `seeusage` CLI command to `~/.local/bin/seeusage`.

The original source builder and installer stay unchanged and do not embed Sparkle. Their App updates button opens this fork's Releases for manual installation. `build_dmg.sh` enables the updater dependency only for packaged releases and embeds its framework and license.

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

# Build and package for both Apple Silicon and Intel Macs
./scripts/build_dmg.sh --universal
```

### DMG distribution

`build_dmg.sh` copies the current package sources into a writable cache under `~/Library/Caches/SeeUsage/dmg-build`, then runs the existing `build_app.sh` there. This avoids permission errors from checkout `.build` or `dist` folders owned by another user and preserves incremental builds. It packages only the app, an Applications shortcut, and installation instructions. With `--universal`, it builds the missing architecture and combines both slices into one app. Omit that flag for your Mac's native architecture. The existing build and install scripts are unchanged.

The output is `dist/SeeUsage-VERSION-ARCH.dmg`, with a matching `.dmg.sha256` checksum. If the checkout's `dist` folder is not writable, the DMG goes into `~/Downloads` instead. Use `--output` to choose another location, or `--app` to package an already built app without compiling:

```bash
./scripts/build_dmg.sh --app dist/build.noindex/SeeUsage.app --output "$HOME/Downloads/SeeUsage.dmg"
cd "$HOME/Downloads"
shasum -a 256 -c SeeUsage.dmg.sha256
```

Combining `--app` with `--universal` requires an app that already contains both architectures.

New DMG builds read their version, increasing build number, feed URL, and public signing key from `release.json`. `--app` retains the supplied bundle's metadata; it does not add an updater to an existing source app. Sparkle is pinned to 2.10.0, and its packaging tools are downloaded into a local cache with a pinned SHA-256 checksum. The DMG contains its framework, helper processes, and license; it has no dependency on that build cache at runtime.

For a Developer ID release, use `--sign "Developer ID Application: YOUR NAME (TEAMID)"`. Signing requires your own certificate in the macOS keychain. Submit the resulting DMG using Apple's `notarytool`, and staple the ticket after acceptance. Signing alone does not notarize the app; follow [Apple's distribution and notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). After stapling, regenerate the `.sha256` file because the DMG has changed. No signing credentials belong in the repository.

### Publishing an update

1. Commit the release sources and update `release.json`: increase **both** `version` and `build` for every release. Build numbers must never be reused, including for replacement assets.
2. Build `./scripts/build_dmg.sh --universal` (optionally with `--sign`), then finish any notarization and stapling.
3. Run `./scripts/prepare_release.sh --dmg "$HOME/Downloads/SeeUsage-1.1.1-universal.dmg"`, adjusting the path/version. It validates the bundle, generates a signed `appcast.xml`, and refreshes the checksum. It never uploads or publishes anything.
4. Create a GitHub release tagged `vVERSION` from the matching commit and upload the **DMG**, its **.dmg.sha256**, and **appcast.xml** together. Publish as a stable release and mark it **latest**. Prereleases do not change the stable update feed.
5. Confirm the latest release's `appcast.xml` asset and the version-specific DMG download are accessible. Already-running apps discover it at their next check; **Check for updates** checks immediately.

The feed is `https://github.com/fabinho5/SeeUsage/releases/latest/download/appcast.xml`, so every stable latest release must include it. A release without that asset breaks update discovery. Generated feeds contain only the current full universal download and require macOS 14+. Do not edit the signed feed or DMG afterward; prepare them again if anything changes. Never replace an already published release's assets with a different build.

The Ed25519 private signing key lives in the publisher's login Keychain under the account in `release.json`; only the public key is committed. `prepare_release.sh` refuses to sign with a different key. Back up the signing key securely outside this repository before relying on updates: losing it prevents signing updates for already installed apps. Other contributors can build DMGs but cannot publish trusted updates without that key. A fork needs its own repository/feed and key pair (generate with Sparkle's `generate_keys --account YOUR_ACCOUNT`), then must set its own public metadata before distributing its first updater-enabled app. Do not commit exported keys or tokens.

Run `python3 -B Tests/UpdaterIntegration/run.py` after a DMG build to test Sparkle against disposable fixture apps and a localhost server. It exercises postpone, skip, current-version, altered-feed, altered-archive, and install/relaunch cases, including preference preservation. It creates a disposable test key and never reads the publisher's Keychain key or launches SeeUsage/provider CLIs. Normal `swift test` uses a fake updater backend and does not need signing credentials. Packaging validation tests run with `python3 -B -m unittest discover -s Tests/UpdaterIntegration -p 'test_*.py'`.

Both the feed and archive are checked against the embedded public key before extraction. This update signature is separate from Developer ID signing and Apple notarization. See [Sparkle's publishing guide](https://sparkle-project.org/documentation/publishing/).

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
    AppUpdater.swift          # Optional Sparkle updates, separate from quota polling
    Theme.swift               # Color palettes for UI and terminal rendering
scripts/
  build_app.sh                # Compiles and bundles dist/build.noindex/SeeUsage.app
  build_dmg.sh                # Packages a native or universal drag-to-install DMG
  prepare_release.sh          # Signs the update feed and validates final release assets
  release_metadata.py         # Configures and validates public release metadata
  sparkle_tools.sh             # Fetches pinned and verified Sparkle release tools
  install.sh                  # Installs to /Applications (fallback ~/Applications) and ~/.local/bin
release.json                  # Version, build number, feed URL, and public update key
assets/                       # Demo media and screen recordings
```

## Contributing

Contributions, bug reports, and feature suggestions are welcome in [this fork’s issues](https://github.com/fabinho5/SeeUsage/issues) and [pull requests](https://github.com/fabinho5/SeeUsage/pulls).

## License

This repository does not currently contain a license file. See [Issues](https://github.com/fabinho5/SeeUsage/issues) to inquire about licensing.

---
name: readme
description: Generate a README.md from an existing codebase. Use when the user types /readme, asks to "write a README", "document this project", "generate a README from the code", or says the README is missing or out of date. Reads code structure, entry points, dependencies, and existing docs to produce a README with real names, real commands, and real examples — not placeholder text. Follows a prioritized feature checklist and annotates what the author still needs to supply (🖊) vs. what was auto-detected (🤖).
---

# Generate README

When invoked, analyze the codebase and produce a `README.md` that accurately
describes the project — what it does, how to install it, and how to use it.

The output is direct and technical. Audience: engineers who've never seen this
repo. Tone: a competent colleague wrote it, not a marketing team.

**Key rule:** use actual names, paths, flags, and values from the code.
No `<your-value-here>` placeholders. No hypothetical examples.

**Auto-detect vs. author input:** throughout the README, mark fields that
need author confirmation with `<!-- 🖊 TODO: ... -->` HTML comments so they
don't render on GitHub but are easy to find. Fields fully derived from code
need no annotation.

---

## Feature priority reference

Use this checklist to decide what to include. Generate everything **Must have**
and **Very nice** by default. Include **Nice to have** and **Optional** only if
signals are present in the repo.

| Priority | Features |
|----------|----------|
| **Must have** | Project name & tagline, elevator pitch, prerequisites, installation, quickstart example, feature walkthrough examples, CLI options reference (CLI tools) or API docs link (libraries), license |
| **Very nice** | Badges row, project status, table of contents (≥4 sections), audience statement, configuration reference, known limitations, contributing guide |
| **Nice to have** | Architecture diagram, comparison to similar tools, troubleshooting / FAQ, changelog link |
| **Optional** | Logo/banner, acknowledgements, contributors section |

**Auto-detectability guide** (🤖 = fully auto, 🔶 = partial, 🖊 = author only):

| Feature | Auto? | Signals |
|---------|-------|---------|
| Project name | 🤖 | Repo name, `Cargo.toml`/`package.json` name, Xcode target `PRODUCT_NAME` |
| Tagline | 🔶 | `package.json`/`Cargo.toml` description — confirm with author |
| Badges (CI, version, license) | 🤖 | `.github/workflows`, `LICENSE`, `Cargo.toml` registry name |
| Project status | 🔶 | Last commit date, release count, open issues — author confirms |
| Table of contents | 🤖 | Generated from H2 headings; skip if < 4 sections |
| Prerequisites | 🤖 | `Cargo.toml` rust-version, `package.json` engines, `Package.swift` `swift-tools-version` and `platforms:`, Xcode deployment target and `SWIFT_VERSION`, CI matrix |
| Installation | 🤖 | Package manager manifest, CI install steps, Makefile, Xcode schemes |
| Quickstart / Hello World | 🔶 | Infer from `examples/`, tests, doctests — author captures screenshots/GIFs |
| Feature list | 🔶 | Draft from `--help`, test names, README prose — author confirms differentiators |
| CLI options reference | 🤖 | clap/argparse/cobra/click/Swift ArgumentParser source definitions, or `CommandLine.arguments` parsing |
| API docs link | 🤖 | `Cargo.toml` (docs.rs URL), `package.json` homepage, `mkdocs.yml`, Swift Package Index / DocC |
| Configuration | 🔶 | dotenv loading, Config struct, `clap` `env()` attrs, config file paths, `UserDefaults` / `@AppStorage` keys, Settings scene |
| Known limitations | 🔶 | `#[cfg(target_os)]`, `#if os(...)`, `@available`, TODO/FIXME comments, open issues — author reviews |
| Architecture diagram | 🔶 | Claude can generate Mermaid from module/import structure |
| Comparison table | 🖊 | Author must validate competitors |
| Contributing | 🔶 | Link `CONTRIBUTING.md` if present; else scaffold from CI steps |
| Changelog | 🤖 | Link `CHANGELOG.md` or `/releases` if present |
| License | 🤖 | `LICENSE` file → SPDX identifier |
| Logo/banner | 🖊 | Claude cannot generate images |
| Screenshots / GIFs | 🖊 | Highest ROI visual; author must capture |

---

## Step 1: Gather context

Read in this order:

### 1a. Existing documentation
```bash
cat README.md 2>/dev/null      # existing README — note what to preserve vs. update
cat CLAUDE.md 2>/dev/null
cat docs/design.md 2>/dev/null
```

If a README already exists, preserve accurate sections; revise stale ones.

### 1b. Project structure
```bash
find . -type f \( -name "*.rs" -o -name "*.py" -o -name "*.ts" \
  -o -name "*.go" -o -name "*.swift" -o -name "*.js" \) \
  | grep -v node_modules | grep -v .build | grep -v target | grep -v .git \
  | grep -v DerivedData \
  | head -60

find . -type d | grep -v node_modules | grep -v target \
  | grep -v .git | grep -v __pycache__ | grep -v DerivedData \
  | grep -v xcuserdata | grep -v '\.xcassets/' | sort | head -40
```

For an Xcode project with the xcode-tools MCP available, also run
`XcodeListTargets` and `XcodeListSchemes`. One repo often holds several
products (e.g. an app plus a command-line tool) — each user-facing product
gets its own section in the README.

### 1c. Entry points and CLI definition

Read the main entry point and files that define user-facing behavior:
- Entry point: `main.rs`, `main.py`, `index.ts`, `cmd/`, `main.swift`, the
  `@main` type (a SwiftUI `App` struct for an app), etc.
- CLI definition: clap (`src/cli.rs`, `src/main.rs`), argparse, cobra, click,
  Swift ArgumentParser (`ParsableCommand`)
- App UI: the root scene and view (`WindowGroup` content, `SKScene`
  subclass) and any keyboard / mouse / touch handling — this is the app's
  "usage"
- Config loading: any file reading env vars or a config file

Focus on what reveals *how a user interacts with this program*.

### 1d. Dependencies and manifest
```bash
cat Cargo.toml 2>/dev/null
cat package.json 2>/dev/null
cat requirements.txt 2>/dev/null
cat go.mod 2>/dev/null
cat Package.swift 2>/dev/null
```

Extract: package name (for badges/install commands), rust-version/engines
(for prerequisites), registry presence (for install method), license.

An Xcode project has no readable manifest. Use `GetTargetBuildSettings`
(xcode-tools MCP) or `xcodebuild -showBuildSettings -target <name>` for
`PRODUCT_NAME`, `SWIFT_VERSION`, and the deployment target
(`MACOSX_DEPLOYMENT_TARGET` / `IPHONEOS_DEPLOYMENT_TARGET`) — these give
the prerequisites. The required Xcode version follows from the Swift
version and SDK; mark it 🖊 if it can't be pinned down. Package
dependencies are in
`*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Don't parse `project.pbxproj` by hand.

### 1e. CI, tests, and examples
```bash
ls .github/workflows/ 2>/dev/null   # CI provider → badge URLs
ls examples/ tests/ 2>/dev/null     # quickstart material
cat Makefile 2>/dev/null            # build/test/install targets
```

### 1f. Limitation signals
```bash
# Platform conditionals
grep -r "cfg(target_os" src/ 2>/dev/null | head -20
grep -rn "#if os(\|#if targetEnvironment\|@available(" --include='*.swift' . 2>/dev/null | head -20
# Known issues (Swift projects often have no src/ — search from the root)
grep -rn "TODO\|FIXME\|HACK\|KNOWN" src/ 2>/dev/null | head -20
grep -rn "TODO\|FIXME\|HACK\|KNOWN" --include='*.swift' . 2>/dev/null | head -20
```

---

## Step 2: Understand the project

Before writing, answer:

1. **One sentence:** what does this program do? (lead with the verb)
2. **Who uses it?** Developer tooling? End users? A pipeline?
3. **What makes it different?** What would you do without it?
4. **Key limitation or trade-off?** Platform support, performance ceiling, scope boundary?
5. **What are the most common workflows?** (the 80% cases)
6. **Project type?** CLI tool → CLI options reference; library → API docs link; GUI app (macOS/iOS) → controls reference (mutually exclusive per product — a repo with an app and a CLI tool gets one of each)

---

## Step 3: Write README.md

Use the CLI tool template below as the primary structure. For libraries,
replace the CLI options reference with an API docs link and quick-start
import snippet. For a GUI app (Xcode app target), make the replacements
in "App variant" after the template.

````markdown
<!-- Logo if author provides one — omit entirely if not yet available -->
<!-- 🖊 TODO: Add logo to docs/images/logo.png and uncomment:
<p align="center">
  <img src="docs/images/logo.png" alt="PROJECT_NAME logo" width="200">
</p>
-->

<!-- Badges — fully auto-generated from repo signals -->
<p align="center">
  <a href="../../actions"><img src="https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/OWNER/REPO" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/OWNER/REPO" alt="License"></a>
</p>

# PROJECT_NAME

> _One-line tagline — the bumper sticker version._

[Elevator pitch: 3–5 sentences. What it does (verb matters). Who it's for.
What makes it different from the obvious alternative. Key limitation or
trade-off. Do NOT just restate the tool name.]

<!-- 🖊 TODO: Set project status — delete the others:
> **Status:** Active development — APIs and CLI flags may change between minor versions.
> **Status:** Stable — breaking changes only on major versions.
> **Status:** Experimental / proof-of-concept — use at your own risk.
> **Status:** Maintenance mode — no new features; bug fixes only.
-->

---

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Examples](#examples)
- [Configuration](#configuration)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Feature one** — why this matters, specifically
- **Feature two** — specific capability, not generic praise
- **Feature three**
- Cross-platform: macOS, Linux _(adjust to match reality)_

---

## Prerequisites

- **[Runtime]**: version X.Y or later
- **[System library]** _(if any)_: `brew install X` / `apt install X`
- **[Hardware]** _(if relevant)_: what must be connected

---

## Installation

### From [registry]
```sh
cargo install PROJECT_NAME   # or: pip install, npm install -g, etc.
```

### From source
```sh
git clone https://github.com/OWNER/REPO.git
cd REPO
cargo build --release
# Binary: ./target/release/PROJECT_NAME
```

<details>
<summary>Pre-built binaries</summary>

Download from the [Releases page](../../releases/latest).

| Platform | File |
|----------|------|
| macOS (Apple Silicon) | `PROJECT_NAME-aarch64-apple-darwin.tar.gz` |
| macOS (Intel)         | `PROJECT_NAME-x86_64-apple-darwin.tar.gz` |
| Linux (x86-64)        | `PROJECT_NAME-x86_64-unknown-linux-gnu.tar.gz` |
</details>

### Verify
```sh
PROJECT_NAME --version
```

---

## Quick Start

<!-- 🖊 TODO: Add a screenshot or GIF here — highest ROI element in a CLI README.
<p align="center">
  <img src="docs/images/demo.gif" alt="PROJECT_NAME demo" width="700">
</p>
-->

```sh
# Most representative one-liner showing core value
PROJECT_NAME [real-args]
```

```
# Expected output (copy the actual output — don't make it up)
...
```

---

## Usage

```
USAGE:
    PROJECT_NAME [OPTIONS] <INPUT>

ARGS:
    <INPUT>    Description

OPTIONS:
    -o, --output <PATH>    Where to write output [default: stdout]
    -v, --verbose          Enable verbose logging
    -h, --help             Print help
    -V, --version          Print version
```

<!-- For tools with subcommands, use a table instead:
| Subcommand | Description |
|------------|-------------|
| `list`     | List available ... |
| `run`      | Run a ... |
-->

---

## Examples

### Basic usage
```sh
PROJECT_NAME input.txt
```

### [Second most common workflow]
```sh
# Annotate anything non-obvious
PROJECT_NAME --flag value input.txt
```

### [Advanced / composed usage]
```sh
PROJECT_NAME --advanced-flag | other-tool
```

---

## Configuration

<!-- Include only if the tool has persistent config (env vars, config file, or both).
     Delete this section entirely if there's nothing to configure. -->

### Config file

The tool looks for config at `~/.config/PROJECT_NAME/config.toml`
(or `$PROJECT_NAME_CONFIG`).

```toml
# ~/.config/PROJECT_NAME/config.toml
option_one = "value"   # description (default: "value")
option_two = 42        # description (default: 42)
```

### Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_NAME_CONFIG` | Path to config file | `~/.config/PROJECT_NAME/config.toml` |
| `PROJECT_NAME_LOG`    | Log level (`error`…`trace`) | `error` |

---

## Known Limitations

- **[Platform not supported]**: explanation or workaround
- **[Performance edge case]**: when and how it manifests
- **[Out of scope]**: what this deliberately doesn't do, and what to use instead

<!-- 🖊 TODO: Review and expand — partially inferred from cfg() guards and TODO comments in source. -->

---

## Contributing

<!-- If CONTRIBUTING.md exists, just link it: -->
See [CONTRIBUTING.md](CONTRIBUTING.md).

<!-- Otherwise inline the basics:
Contributions welcome.

```sh
git clone https://github.com/OWNER/REPO.git
cd REPO
cargo test
cargo clippy
```

Please open an issue before starting significant work.
-->

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

## License

Licensed under the **MIT License** — see [LICENSE](LICENSE) for details.
````

### App variant (Xcode app target)

Replace these sections of the template; keep the rest.

- **Prerequisites** — macOS version to build on, Xcode version, and the
  app's deployment target and platforms, from Step 1d. Example:
  `- **Xcode** 26 or later` / `- Runs on **macOS 15** or later`.
- **Installation** — "From source" only, unless the repo shows a release
  or App Store / TestFlight link:
  ````markdown
  ```sh
  git clone https://github.com/OWNER/REPO.git
  open REPO/PROJECT.xcodeproj
  ```
  Select the `SCHEME` scheme and **My Mac** (or a simulator), then press ⌘R.

  Command line:
  ```sh
  xcodebuild -project PROJECT.xcodeproj -scheme SCHEME -configuration Release build
  ```
  ````
  If the app needs a signing team to run (entitlements, capabilities),
  say so with a 🖊 TODO — signing setup is author-only knowledge.
- **Verify** — delete it; an app has no `--version`.
- **Quick Start** — what the user sees on launch and the first thing to
  do. The screenshot TODO moves to the top of this section, and is
  required, not optional.
- **Usage** → **Controls** — a table of the real keyboard, mouse, and
  touch inputs, read from the event-handling code (`keyDown`,
  `mouseDown`, `onKeyPress`, gestures, menu commands). Don't invent any.
- **Configuration** — Settings-scene options and `UserDefaults` /
  `@AppStorage` keys, if any; otherwise delete it.
- **Contributing** — build and test with ⌘B / ⌘U, or
  `xcodebuild test -scheme SCHEME`, in place of `cargo test`.

A command-line tool target in the same repo (e.g. a `tools/` target)
gets its own short section with the CLI template's Usage block, built
with `xcodebuild -scheme <tool> build` or run from Xcode.

---

## Writing guidelines

**Lead with the elevator pitch, not the one-liner.** A tagline is a bumper
sticker; the elevator pitch (3–5 sentences: what, who, differentiator,
trade-off) is what makes someone decide to keep reading. Both belong.

**Real values everywhere.** Extract actual flag names from the CLI source.
Pull actual output from `examples/` or tests. Never invent examples.

**Screenshots and GIFs have the highest ROI of any README element.** Claude
cannot generate them — leave `<!-- 🖊 TODO -->` comments where they belong
so the author knows exactly where to drop them.

**CLI tools get a Usage section; libraries get an API docs link; apps get
a Controls section.** These are mutually exclusive per product. Don't
include two for the same product.

**Known Limitations builds trust.** A README with no caveats reads as
incomplete or dishonest. Scan `#[cfg(target_os)]`, `#if os(...)`,
`@available`, TODO/FIXME comments,
and open issues tagged "known issue" or "wontfix" to populate this section.
Mark it for author review.

**Omit sections that don't apply.** No config file → delete Configuration.
No persistent state → delete that env var table. Shorter is better when the
content would be invented.

**Table of contents:** auto-generate from H2 headings. Include only if the
README has 4+ sections.

---

## Step 4: Write the file

Write to `README.md` at the project root.

If a README already existed, note which sections you updated vs. preserved.

---

## Step 5: Present a summary

Tell the developer:
1. Sections written and their auto-detect status
2. `<!-- 🖊 TODO -->` items that need author input (logo, status, screenshots,
   comparison table, limitation review)
3. Any sections omitted and why

Then ask: **"Does this README accurately represent the project? Anything
missing or wrong?"**

Edit in place if they want revisions.

---

## Step 6: Offer next steps

After confirmation:

- "Want me to stage this for your next commit?"
- If `docs/design.md` doesn't exist: "The README covers the 'what' — want me
  to run `/design-doc` to capture the 'why' in a design doc?"
- If no `CLAUDE.md`: "Want a `CLAUDE.md` too for future Claude Code sessions?"
- If the quickstart has no screenshot: "A demo GIF here would be the
  highest-ROI improvement — record one with `vhs` or QuickTime and I can embed it."
  For an app, with the xcode-tools MCP available, offer to take the
  screenshot: run the app (`RunProject`) and capture it with the
  `xcode-integration:device-interaction` skill.

---

## What not to do

- Don't use placeholder text (`<your-repo>`, `YOUR_VALUE`) in the output —
  leave `<!-- 🖊 TODO -->` comments for things that need author input
- Don't describe features that don't exist yet as if they do
- Don't include more than one of CLI options reference, API docs link, and
  Controls for the same product — pick one
- Don't invent flag names — read the CLI source definition
- Don't skip Known Limitations — it's what separates trustworthy docs from polished fiction
- Don't pad with generic boilerplate unrelated to this specific project

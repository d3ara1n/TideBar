# TideBar Project Conventions

A macOS Dock replacement: normally collapses into a thin line at the bottom of the screen and expands like a tide when the pointer approaches. See `docs/product.md` for full product positioning.

## Mental Model

- **Product soul = zero presence + full Dock functionality**: Barely visible as a thin line when idle; matches system Dock capabilities when expanded. Every implementation tradeoff serves this goal.
- **Reuse system capabilities instead of reimplementing**: Launching, running-app lists, context menus, Trash, etc. use system frameworks (`NSWorkspace`, `NSMenu`, `FSEvents`, `AX`, `ScreenCaptureKit`). Spend effort only on differentiated interactions and window experience.
- **Window layering and event model are foundational**: The `NSPanel` combination of `styleMask`, `level`, and `collectionBehavior` governs all behavior; verify window-layer constraints before changing interactions (see `docs/decisions.md` for the rationale behind each constraint).

## Environment

- Development machine: macOS 27 beta, Apple Silicon; Xcode 27 (`27A266a`).
- Tech stack: Swift 6 + SPM (`swift-tools` 6.2, minimum macOS 14), **light third-party dependencies** (only small, focused single-purpose libraries; no heavy frameworks), no Xcode project file.
- Bundle ID: `dev.dearain.TideBar`.

## Build and Verification

- Build and run during development with the legacy backend explicitly: `swift build --build-system native` to compile, `swift run --build-system native` to run (occupies the terminal; exit with `Ctrl-C`). Release packaging uses `scripts/build-app.sh` with `swiftbuild` so dependency resource lookup fits standard `.app/Contents/Resources`; the script writes the real SDK via linker `platform_version` and gates with `vtool` to prevent Xcode 27 from miswriting the SDK as the deployment target (tracked in `plans/`).
- **Agent verification stops at `swift build`**: GUI runtime verification is performed by the user running `swift run` and interacting with the UI; do not run launch-wait-kill automated smoke cycles.
- System-level commands (such as `defaults write` to hide the system Dock) are only printed for the user to run, or executed only after explicit confirmation—never modified silently.

## Documentation Map

| Document | Contents | Lifecycle |
|---|---|---|
| `docs/product.md` | Product positioning, core interaction, naming, benchmarks | Very stable |
| `docs/glossary.md` | English and Chinese product terms and definitions | Updated alongside naming/meaning changes |
| `docs/decisions.md` | Settled architectural decisions, feasibility boundaries, permission policy | Truth of current state; check `git log` for history |
| `docs/research-dock-alternatives.md` | Research archive on similar apps (facts and approaches) | Frozen per research snapshot |
| `plans/` | Filed tasks (single source of truth for current work) | See below |

## `plans/` Discipline

- `todo-<date>-<topic>.md`: Filed task. Move to `plans/archived/` upon completion; promote lasting conclusions to `docs/`.
- `plans/archived/`: Completed plans; append-only (never moved out).
- **Deferral means filing**: Unfinished or deferred work must be recorded in `plans/`; chat is ephemeral, and unrecorded decisions do not count as having happened.
- Filenames declare lifecycle directly; add new prefixes as needed (all-caps for standing manuals), provided their lifecycle can be stated in one sentence.

## Decision Boundaries

- **Agent-autonomous**: Internal class decomposition, animation implementation, naming, code organization, implementation-level parameters.
- **Requires user decision**: Interaction paradigm changes, system-level modifications, capabilities requiring user permissions (Screen Recording / Accessibility), adding third-party dependencies (only lightweight single-purpose libraries are acceptable).

## Conventions

### Branches and PRs

- `main` is branch-protected: all changes go through an independent branch and PR squash-merged into `main` rather than developing directly on `main`; one PR produces one merge commit.
- During implementation, agents may create branches, commit, push, and open/update PRs; PRs must remain open until the user explicitly confirms acceptance. Do not merge, delete local/remote branches, or run post-merge local sync before user acceptance.
- Explicit user acceptance grants full merge-lifecycle permission for that change: pushing, remote squash merge, branch deletion, and local pull/sync may proceed without asking step by step.
- CI is a mandatory merge gate for non-admin contributors; admins are permanently exempt from the gate, yet still land changes via branch + PR and satisfy local verification and user acceptance. Infrastructure failures (such as CI dependency downloads) do not equal test failures and must never be spoofed; when merging as admin using local test results, note the verification basis and remote blocker in the PR.
- The PR title becomes the merge commit subject using Conventional Commits (see Language Conventions); batched PRs use the dominant type and list each task in the body. Process commits inside a branch are free-form; only the final squash message matters.
- Tag every PR with a label for release-note grouping (`.github/release.yml`): `feature`/`enhancement` → Features, `bug`/`fix` → Bug Fixes, `documentation` → Documentation; `chore-release` PRs are excluded from release notes.
- Versioning and releases are automated by release CI (computed weekly on Monday from merge commits); do not tag manually.

### Language Conventions

- **User-facing copy is bilingual, English first**: README, website, and software UI use English as the primary language and Simplified Chinese (`zh-Hans`) as the secondary language. Explain actual features and usage tailored to each medium; see `docs/glossary.md` for product terms.
- **Developer documents follow the developer's language (Chinese) where established**: `docs/`, `plans/`, code comments, and commit subjects are written in Chinese for developer clarity; `docs/glossary.md` records both English and Chinese names. `AGENTS.md` itself is written in English.
- Runtime logs (`NSLog`) use formal English so they remain greppable.
- Commit messages use Conventional Commits (lowercase English type: `feat`/`fix`/`docs`/`chore`/`refactor`…, Chinese subject).
- AI-assisted commits include both a `Co-Authored-By` trailer for the model and an `Agent-Harness` trailer for the agent software in one contiguous trailer block (under the PR workflow, write them in the PR description so squash merge carries them into the merge commit body):
  ```text
  Co-Authored-By: <model-id> <provider-noreply>
  Agent-Harness: <harness-name> (<harness-url>)
  ```
  - **Model ID**: Obtain the actual model name from available environment information before each commit (or PR) rather than reusing an earlier trailer, and extract the vendor's model ID; ask the user only when it cannot be determined. Drop relay prefixes (such as `provider/`), channel markers (such as `[Kiro]`), and variant suffixes (such as `-thinking` or `-high`), so `[Kiro]claude-opus-5-5-thinking` becomes `claude-opus-5-5`.
  - **Provider email**: Always use the model vendor's noreply address regardless of relay or channel: `noreply@anthropic.com` (`claude-*`), `noreply@openai.com` (`gpt-*`, `o1*`, `o3*`, `o4*`, `codex-*`), `noreply@google.com` (`gemini-*`), `noreply@x.ai` (`grok-*`), `noreply@deepseek.com` (`deepseek-*`), `noreply@qwenlm.ai` (`qwen*`), `noreply@zhipuai.cn` (`glm-*`), `noreply@moonshot.cn` (`kimi-*`), or the known vendor's noreply address for other vendors. Only when the model vendor is genuinely unknown, use `noreply@unknown.invalid`; never invent a vendor domain or reuse an unrelated tool domain.
  - **Agent harness**: Identify the agent software from available environment information and include its canonical homepage URL in parentheses when known (for example, `Agent-Harness: Asterism (https://asterism.dearain.dev)`). If the harness URL is unknown, omit the parenthesized URL and write only `<harness-name>` rather than guessing.
- Keep code and documentation free of "was A, changed to B" historical residue; use `git log` for history.

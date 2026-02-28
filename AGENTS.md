# Repository Guidelines

## Project Structure & Module Organization
The app code lives in `Klaro/` and follows an MVVM + service-layer split:
- `App/` for app entry, global state, commands, and theme
- `Models/` for shared domain types
- `Services/` for actor-isolated Kubernetes and system integrations
- `ViewModels/` for `@MainActor` UI orchestration
- `Views/` grouped by feature (`Workloads`, `Network`, `Storage`, etc.) plus `Layout` and `Shared`
- `Utilities/` for extensions, constants, and shortcuts
- `Resources/Assets.xcassets` for app assets

Tests are in `KlaroTests/` (unit) and `KlaroUITests/` (UI launch/smoke). `project.yml` is the XcodeGen source of truth; `Klaro.xcodeproj` is generated output.

## Build, Test, and Development Commands
- `open Klaro.xcodeproj` — open and run from Xcode (`Cmd+B`, `Cmd+R`).
- `xcodegen generate` — regenerate the project after editing `project.yml`.
- `xcodebuild -project Klaro.xcodeproj -scheme Klaro -destination 'platform=macOS' build` — CLI build.
- `xcodebuild -project Klaro.xcodeproj -scheme Klaro -destination 'platform=macOS' test` — run unit + UI tests.

If auth plugins are used in kubeconfig, install required binaries (`azure-kubelogin`, `gcloud`, `aws-iam-authenticator`) before manual testing.

## Coding Style & Naming Conventions
Use Swift 6 conventions already present in the repo:
- 4-space indentation, no tabs
- `PascalCase` for types, `camelCase` for methods/properties
- Clear suffixes: `*View`, `*ViewModel`, `*Service`
- Organize files with `// MARK:` sections

Prefer strict concurrency-safe design: actor services for async stateful work, `@MainActor` view models for UI updates.

## Testing Guidelines
Write unit tests with Swift Testing (`import Testing`, `@Test`, `#expect`) in `KlaroTests/`. Keep UI flow checks in `KlaroUITests/` using `XCTest`.

Name tests by behavior (for example, `appStateDefaults`, `resourceKindCategories`) and add coverage for new model mapping, view-model state transitions, and service error paths.

## Commit & Pull Request Guidelines
Recent history uses short imperative summaries (for example, `Enhance ...`, `Implement ...`, `Refactor ...`). Keep commits focused and descriptive, one change set per commit.

PRs should include:
- what changed and why
- linked issue/ticket (if any)
- validation notes (build/tests run)
- screenshots or recordings for UI/layout changes

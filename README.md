# Leme

[![CI](https://github.com/neoemu/leme/actions/workflows/ci.yml/badge.svg)](https://github.com/neoemu/leme/actions/workflows/ci.yml)

A native macOS Kubernetes IDE built with SwiftUI. A lightweight, fast alternative to [Lens](https://k8slens.dev/) — no Electron, no web stack, pure Apple-native experience.

> **Why "Leme"?** The Kubernetes logo is a ship's wheel — the helm. In Portuguese, that's the **leme**. *Estar ao leme* means to be at the helm, in command. Leme puts your hands on it.

## Why Leme?

Lens is a powerful Kubernetes IDE, but it runs on Electron — consuming significant memory and CPU. Leme delivers the same core experience as a native macOS app:

| | Lens | Leme |
|---|---|---|
| Runtime | Electron (Chromium) | Native macOS (SwiftUI) |
| Memory | ~500MB+ | ~50MB |
| Startup | 3-5s | <1s |
| UI Framework | React | SwiftUI |
| Binary size | ~250MB | ~15MB |
| macOS integration | Limited | Full (Keychain, Spotlight, system theme) |

## Features

### Multi-cluster management
- Auto-detects clusters from `~/.kube/config`
- Hotbar with cluster icons for quick switching
- Per-cluster connection lifecycle (connect/disconnect)
- Supports all auth methods: token, certificate, exec-based (Azure AD/kubelogin, gcloud, aws-iam-authenticator)

### Resource browser
- **26 Kubernetes resource types** organized by category:
  - **Cluster**: Nodes, Namespaces
  - **Workloads**: Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, ReplicaSets
  - **Network**: Services, Ingresses, Endpoints, NetworkPolicies
  - **Configuration**: ConfigMaps, Secrets
  - **Storage**: PVCs, PVs, StorageClasses
  - **Access Control**: ServiceAccounts, Roles, ClusterRoles, RoleBindings, ClusterRoleBindings
  - **Events**: Cluster events
- Sortable, searchable tables with context menus
- Namespace filtering (single namespace or all)
- Detail panel with metadata, labels, annotations, spec, status

### Real-time log streaming
- Stream pod logs via AsyncSequence
- Follow mode (auto-scroll)
- Container selector for multi-container pods
- Search within logs
- Timestamp toggle

### Integrated terminal
- Local shell sessions with `KUBECONFIG` pre-configured
- `kubectl exec` into pods directly from context menu
- Multiple terminal tabs
- Powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)

### YAML editor
- View and edit resource YAML
- Syntax highlighting via [CodeEditor](https://github.com/ZeeZide/CodeEditor)
- **Git-style diff review before every apply** — see exactly what changes hit the cluster
- Merge-patch of only the changed fields, with `kubectl apply` fallback

### Helm
- Installed releases with status, chart, and revision
- Revision history with one-click **rollback**
- Values per revision (user-supplied or computed `--all`) and rendered manifest
- Uninstall with confirmation
- Compatible with helm 3 and 4

### Troubleshooting ("Problems")
- One view of everything broken right now: CrashLoopBackOff, ImagePull errors, unschedulable/OOM-killed pods, degraded workloads, NotReady nodes, pending PVCs, failed jobs
- Correlated Warning events per problem, expandable inline
- Live count badge in the sidebar (red = criticals)
- Jump straight to the affected resource or its logs

### Production guard-rails
- Clusters auto-detected as PROD/STG/DEV/TEST by name (overridable per cluster)
- Red PRODUCTION banner on prod clusters
- Destructive operations (delete, restart, drain, rollback, uninstall, YAML apply) require **typing the resource/cluster name** to confirm — GitHub style

### SRE workflows
- Port-forward manager with suggested ports and active-forward badge
- Node cordon/uncordon/drain
- Workload rollout restart and rollback
- Secret decode with reveal/copy
- Multi-pod (stern-style) workload logs
- Namespace management (create/delete, use-as-filter)

### Command palette
- `Cmd+Shift+P` to open
- Fuzzy search across navigation, cluster operations, and contextual actions on the selected resource
- Keyboard-driven workflow with production confirmations preserved

## Screenshots

*Coming soon — the app is functional and connecting to real clusters.*

## Architecture

```
MVVM + Service Layer

Views (SwiftUI)  →  ViewModels (@Observable)  →  Services (actors)  →  SwiftkubeClient
                           │
                     AppState (@Observable)
                   passed via @Environment
```

### Layout (flat chrome, hidden title bar)

```
┌──────────────────┬──────────────────────────────────────────────┐
│ Cluster switcher │  Top strip (sidebar toggle · reload · port-  │
│ Namespace filter │  forwards · inspector · settings)            │
│                  ├──────────────────────────────────────────────┤
│ Cluster          │                                              │
│   Problems  (3)  │  ResourceTable        │ Inspector (slide-in) │
│   Nodes          │                       │  or YAML editor      │
│ Workloads        │                       │                      │
│   Pods           ├───────────────────────┴──────────────────────┤
│   Deployments    │  Bottom Panel (Logs / Terminal)              │
│ Apps · Helm      │                                              │
│ More Resources   │                                              │
└──────────────────┴──────────────────────────────────────────────┘
```

### Tech stack

| Dependency | Purpose |
|---|---|
| [SwiftkubeClient](https://github.com/swiftkube/client) | Kubernetes API client (list, get, watch, logs) |
| [SwiftkubeModel](https://github.com/swiftkube/model) | Typed K8s resource structs |
| [Yams](https://github.com/jpsim/Yams) | YAML parsing (kubeconfig, manifests) |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator (pod exec, local shell) |
| [CodeEditor](https://github.com/ZeeZide/CodeEditor) | YAML syntax highlighting editor |

### Concurrency model

- **Swift 6 strict concurrency** throughout
- Services are `actor`-isolated (`ClusterManager`, `KubernetesService`, `ResourceWatcher`)
- ViewModels are `@MainActor @Observable`
- Watch streams use `AsyncThrowingStream` with exponential backoff reconnect

## Project structure

```
Leme/
├── App/
│   ├── LemeApp.swift                 # @main entry point
│   ├── AppState.swift                 # Global observable state
│   ├── AppCommands.swift              # Menu bar commands + shortcuts
│   └── Theme.swift                    # Colors, fonts, dark/light tokens
├── Models/
│   ├── ClusterConnection.swift        # Cluster connection model
│   ├── ResourceKind.swift             # 26 K8s resource types enum
│   ├── ResourceCategory.swift         # Sidebar categories
│   └── BottomPanelMode.swift          # logs / terminal / yaml
├── Services/
│   ├── ClusterManager.swift           # Kubeconfig parsing, client lifecycle
│   ├── KubernetesService.swift        # Generic K8s API facade (list/get/watch/delete)
│   ├── ResourceWatcher.swift          # Watch streams with auto-reconnect
│   ├── LogStreamService.swift         # Pod log streaming
│   └── ExecService.swift              # kubectl exec process spawning
├── ViewModels/
│   ├── ClusterViewModel.swift         # Cluster connection lifecycle
│   ├── ResourceListViewModel.swift    # Generic resource list (search, sort, filter)
│   ├── ResourceDetailViewModel.swift  # Resource detail + YAML
│   ├── PodLogsViewModel.swift         # Log streaming state
│   ├── TerminalViewModel.swift        # Terminal session management
│   └── CommandPaletteViewModel.swift  # Fuzzy search actions
├── Views/
│   ├── Layout/                        # MainLayout, Hotbar, Sidebar, Content, BottomPanel
│   ├── Cluster/                       # ClusterOverview, NodeList
│   ├── Workloads/                     # Pod, Deployment, StatefulSet, DaemonSet, Job, CronJob
│   ├── Network/                       # Service, Ingress, Endpoint
│   ├── Configuration/                 # ConfigMap, Secret
│   ├── Storage/                       # PVC, PV, StorageClass
│   ├── AccessControl/                 # ServiceAccount, Role
│   ├── Events/                        # EventList
│   └── Shared/                        # ResourceTable, DetailPanel, LogViewer, Terminal, etc.
├── Utilities/
│   ├── Constants.swift
│   ├── KeyboardShortcuts.swift
│   └── Extensions/                    # Date+RelativeTime, Color+Theme
└── Resources/
    └── Assets.xcassets
```

**~90 Swift source files — ~20,000 lines of code.**

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- Swift 6.0
- A valid `~/.kube/config` with at least one cluster context

## Getting started

### Install (download)

Grab the latest DMG from [Releases](https://github.com/neoemu/leme/releases), open it and drag **Leme** to Applications.

Leme is not notarized yet, so macOS blocks the first launch. Either go to **System Settings → Privacy & Security** and click **Open Anyway**, or clear the quarantine flag:

```bash
xattr -d com.apple.quarantine /Applications/Leme.app
```

### Build and run

```bash
# Clone
git clone git@github.com:neoemu/leme.git
cd leme

# Open in Xcode
open Leme.xcodeproj

# Build: Cmd+B
# Run:   Cmd+R
```

### Regenerate Xcode project (if needed)

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project file generation:

```bash
brew install xcodegen
xcodegen generate
```

### Auth plugins

If your kubeconfig uses exec-based authentication (Azure AD, GCP, AWS), ensure the auth binary is installed:

```bash
# Azure AD
brew install azure-kubelogin

# GCP
brew install --cask google-cloud-sdk

# AWS
brew install aws-iam-authenticator
```

Leme automatically adds `/opt/homebrew/bin`, `/usr/local/bin`, and other common paths to `PATH` at runtime so auth plugins are found even when launched from Xcode or Finder.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+P` | Command palette — navigation, cluster ops, and actions on the **selected resource** (logs/shell/delete for pods, restart/rollback for workloads, cordon/uncordon/drain for nodes) |
| `Cmd+K` | Global search across all namespaces (resources + helm releases) |
| `Cmd+Shift+L` | Open the logs panel |
| `Cmd+Shift+T` | Open the local terminal |
| `Cmd+Shift+D` | Toggle the detail inspector |
| `Cmd+Shift+J` | Close the bottom panel |
| `Cmd+S` | Apply (inside the YAML editor, after the diff review) |

Tips: single-click selects a row (that's what palette actions operate on); double-click opens the detail inspector. Destructive palette actions on production clusters still require the type-to-confirm step.

## Current status

### Working
- [x] Kubeconfig auto-detection, parsing, and file watcher (auto-reload on change)
- [x] Multi-cluster connection management with exec-based auth (kubelogin, gcloud, aws-iam-authenticator)
- [x] Real-time resource updates via the K8s watch API (incremental, no polling)
- [x] Resource browsing for all built-in types + CRDs (grouped by API group)
- [x] Pod log streaming (single pod and stern-style multi-pod), pod exec shell
- [x] YAML edit with diff review and merge-patch apply
- [x] Helm release management (history, rollback, values, manifest, uninstall)
- [x] Problems view with sidebar badge
- [x] Port-forward manager, cordon/drain, rollout restart/rollback
- [x] Production guard-rails (type-to-confirm on destructive ops)
- [x] Global search (Cmd+K) and operational command palette (Cmd+Shift+P)
- [x] Node metrics charts (CPU/memory via metrics-server)
- [x] Namespace management

### Planned
- [x] CI + release pipeline (GitHub Actions; tag `v*` → ad-hoc-signed DMG on Releases)
- [ ] App icon and screenshots
- [ ] Code signing + notarization, Homebrew cask, Sparkle auto-update
- [ ] Multi-window support
- [ ] Light theme refinements

## License

MIT

---

Built with SwiftUI and a lot of mate.

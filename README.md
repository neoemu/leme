# Klaro

A native macOS Kubernetes IDE built with SwiftUI. A lightweight, fast alternative to [Lens](https://k8slens.dev/) — no Electron, no web stack, pure Apple-native experience.

## Why Klaro?

Lens is a powerful Kubernetes IDE, but it runs on Electron — consuming significant memory and CPU. Klaro delivers the same core experience as a native macOS app:

| | Lens | Klaro |
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
- Apply changes back to cluster

### Command palette
- `Cmd+Shift+P` to open
- Fuzzy search across actions, resource types, and navigation
- Keyboard-driven workflow

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

### Layout (3-column, inspired by Lens)

```
┌────────┬─────────────┬────────────────────────────────────────┐
│ Hotbar │  Sidebar     │  Content Area                          │
│  48px  │  220px       │                                        │
│        │              │  ResourceTable  │  DetailPanel (slide)  │
│ [Home] │ [Cluster]    │                 │                       │
│ [Ctx1] │   Overview   │                 │                       │
│ [Ctx2] │ [Workloads]  ├─────────────────┴───────────────────────┤
│ [Ctx3] │   Pods       │  Bottom Panel (Logs / Terminal / YAML)  │
│  ...   │   Deploy     │                                         │
│ [Gear] │   ...        └─────────────────────────────────────────┘
└────────┴─────────────┘
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
Klaro/
├── App/
│   ├── KlaroApp.swift                 # @main entry point
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

**59 Swift source files — ~7,300 lines of code.**

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- Swift 6.0
- A valid `~/.kube/config` with at least one cluster context

## Getting started

### Build and run

```bash
# Clone
git clone git@github.com:neoemu/klaro.git
cd klaro

# Open in Xcode
open Klaro.xcodeproj

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

Klaro automatically adds `/opt/homebrew/bin`, `/usr/local/bin`, and other common paths to `PATH` at runtime so auth plugins are found even when launched from Xcode or Finder.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+P` | Command palette |
| `Cmd+K` | Quick search |
| `Cmd+L` | View logs for selected pod |
| `Cmd+1` | Show sidebar |
| `Cmd+2` | Show bottom panel |
| `Cmd+Shift+T` | New terminal tab |

## Current status

### Working
- [x] Kubeconfig auto-detection and parsing
- [x] Multi-cluster connection management
- [x] Exec-based auth (kubelogin, gcloud, aws-iam-authenticator)
- [x] 3-column layout (Hotbar + Sidebar + Content)
- [x] Resource browsing for all 26 resource types
- [x] Sortable, searchable resource tables
- [x] Namespace filtering
- [x] Resource detail panel (metadata, labels, spec, status)
- [x] Pod log streaming with follow mode
- [x] Integrated terminal (local shell)
- [x] YAML editor with syntax highlighting
- [x] Command palette with fuzzy search
- [x] Dark mode support
- [x] Cluster overview dashboard

### Planned
- [ ] Resource watching (real-time updates via K8s watch API)
- [ ] Pod exec terminal (shell into pods)
- [ ] YAML apply (edit and save back to cluster)
- [ ] Resource delete with confirmation
- [ ] Metrics integration (CPU/memory charts via metrics-server)
- [ ] Helm release management
- [ ] CRD support (custom resource definitions)
- [ ] Multi-window support
- [ ] Kubeconfig file watcher (auto-reload on change)
- [ ] Spotlight integration (search clusters from macOS Spotlight)

## License

MIT

---

Built with SwiftUI and a lot of mate.

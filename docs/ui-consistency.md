# UI Consistency Guardrails

This document preserves the current interaction and visual consistency baseline for Leme's sidebar and resource lists.

## Goals
- Keep navigation and tables consistent across all sections.
- Avoid regressions where interactions only work when clicking text/icon hotspots.
- Keep selection visuals subtle and uniform.
- Preserve fast, responsive behavior from shared list rendering.

## Resource List Standard
- Use `ResourceTableView` for resource listing screens.
- New list views should not be implemented with direct SwiftUI `Table` unless there is a very specific reason.
- Keep shared action surface parity:
  - `Details`
  - `Edit YAML` (when supported)
  - `Download YAML` (when supported)
  - `Delete` (when supported)

## Row Interaction Contract
- Single-click anywhere in row selects the row.
- Double-click anywhere in row opens Details (inspector panel).
- Context menu on row must match the actions menu (`...`) for that resource.
- Avoid requiring clicks only on text labels.

## Selection Styling Contract
- Selected row highlight must use `Theme.Colors.tableSelectionBackground`.
- Do not apply a different/high-intensity selection color in `More Resources`.
- Keep the same selected-row appearance across built-in resources and CRDs.

## Sidebar Interaction Contract
- Section expand/collapse works by clicking the full header row.
- Row selection works by clicking the full row.
- Chevron-only click targets are not acceptable for core navigation flows.

## CRD / More Resources Contract
- Keep `SelectedCustomResourceListView` aligned with `ResourceTableView` behavior.
- Custom resource delete confirmation should include kind + namespace + name for clarity.
- CRD rows must open details with double-click the same way as built-in resources.

## Quick Regression Checklist
Run this checklist after sidebar/table changes:

1. Click empty area of a row (not text): row selects.
2. Double-click empty area of selected row: details inspector opens.
3. Right-click row and open `...` menu: action sets are aligned.
4. `More Resources` selection color matches other tables (subtle highlight).
5. Sidebar group open/close works by clicking the whole group header line.
6. Sidebar item open works by clicking the whole item line.
7. YAML editor and inspector still open/close correctly when switching rows.
8. Counts and refresh behavior in sidebar remain responsive.

## Current Source of Truth Files
- `Leme/Views/Shared/ResourceTableView.swift`
- `Leme/Views/Layout/SidebarView.swift`
- `Leme/Views/Layout/ContentAreaView.swift`
- `Leme/App/Theme.swift`

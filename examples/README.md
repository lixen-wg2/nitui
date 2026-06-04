# Demo

The demo application lives in this directory and is the fastest way to try NitUI.

## Run it

From the repo root:

```sh
cd examples
./run.sh
```

## What it shows

- Terminal UI rendering with focus and keyboard/mouse navigation
- Built-in widgets: tabs, tables, lists, trees, scroll containers, buttons, inputs, modals, sparklines, progress bars
- Multi-screen navigation with push/pop (see `demo_home`, `demo_processes`, `demo_network`, etc.)
- Virtual scrolling tables with row providers
- Mouse click and scroll wheel support

## Demo screens

| Module | Description |
|--------|-------------|
| `demo_home` | Landing page with quick-action buttons |
| `demo_processes` | Live process list with detail drill-down |
| `demo_network` | Network statistics with sparklines |
| `demo_ets` | ETS table browser |
| `demo_widgets` | Widget showcase with list, tabs, scroll, and table views |
| `demo_virtual` | Virtual scrolling table demo |

## Keys

- **Tab / Shift+Tab** — cycle focus between containers
- **Arrow keys** — navigate within tables, lists, trees
- **Enter** — activate focused element
- **PgUp / PgDn** — page navigation
- **Q / ESC** — quit or go back

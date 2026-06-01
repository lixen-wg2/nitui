# NitUI

A Nitrogen-inspired terminal UI framework for Erlang/OTP.

## Features

- **Declarative UI** — build views with nested element records (`#box{}`, `#table{}`, `#tabs{}`, `#list{}`, `#tree{}`, `#scroll{}`, `#input{}`, `#button{}`, `#modal{}`, etc.)
- **Focus management** — container/child navigation with Tab, Arrow, and Page keys
- **Mouse support** — click and scroll wheel via SGR extended mode
- **Virtual scrolling** — tables with row providers for large datasets
- **Differential rendering** — only redraws changed cells for efficient updates
- **ANSI styling** — fg, bg, bold, dim, underline, italic
- **Unicode** — wide-character and emoji support
- **Terminal resize** — automatic SIGWINCH handling
- **Multi-view navigation** — push/pop view stack for screen transitions

## Quick start

```sh
rebar3 compile
cd examples
./run.sh
```

## Learn more

- [Documentation](docs/README.md)
- [Demo guide](examples/README.md)
- [Design notes](nitui.md)

## Requirements

- Erlang/OTP 29+ (uses `prim_tty` for raw terminal access and `io_ansi` for terminal control)
- A terminal emulator with ANSI and SGR mouse support

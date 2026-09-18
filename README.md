# NitUI

A Nitrogen-inspired terminal UI framework for Erlang/OTP.

<img src="guides/assets/nitui-demo.gif" alt="NitUI terminal demo" width="900">

## Features

- **Declarative UI** — build views with nested element records (`#box{}`, `#table{}`, `#tabs{}`, `#list{}`, `#tree{}`, `#scroll{}`, `#input{}`, `#button{}`, `#modal{}`, etc.)
- **Focus management** — container/child navigation with Tab, Arrow, and Page keys
- **Mouse support** — click, drag and scroll wheel via SGR extended mode
- **Virtual scrolling** — tables with row providers for large datasets
- **Differential rendering** — only redraws changed cells
- **ANSI styling** — fg, bg, bold, dim, underline, italic
- **Unicode** — display-width layout for wide characters and emoji
- **Terminal resize** — automatic SIGWINCH handling
- **Multi-view navigation** — push/pop view stack, modals and fullscreen

## Install

```erlang
%% rebar.config
{deps, [nitui]}.
```

```erlang
%% src/my_tui.app.src
{applications, [kernel, stdlib, nitui]}.
```

## Try the demo

```sh
rebar3 compile
cd examples
./run.sh
```

## Documentation

Full documentation is on [HexDocs](https://hexdocs.pm/nitui).

- [Overview](guides/overview.md)
- [Quick start](guides/quick-start.md)
- [Your first application](guides/first-app.md)
- [Elements](guides/elements.md)
- [Events](guides/events.md)
- [Architecture](guides/architecture.md)
- [Demo guide](examples/README.md)

Build the docs locally with `rebar3 ex_doc`.

## Requirements

- Erlang/OTP 29+ (uses `prim_tty` for raw terminal access and `io_ansi` for terminal control)
- A terminal emulator with ANSI and SGR mouse support
- A VM that owns the terminal: `-noinput` (and `+Bc` for Ctrl+C). Do not start a
  UI in an interactive shell VM.

## Test

```sh
rebar3 eunit
```

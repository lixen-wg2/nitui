# Documentation

## Read next

- [Vision and design notes](../nitui.md)
- [Demo guide](../examples/README.md)

## Project structure

```
src/                  Framework runtime
  nit_server.erl      Main gen_server (event loop, rendering, state)
  nit_engine.erl      Shared navigation, pagination, focus, input logic
  nit_tty.erl         Low-level terminal I/O via prim_tty/io_ansi
  nit_terminal.erl    OTP 29 terminal backend and capability facade
  nit_input.erl       ANSI input parser (keys, mouse SGR)
  nit_render.erl      Element tree → screen buffer renderer
  nit_screen.erl      Cell-based screen buffer with diffing
  nit_ansi.erl        Compatibility helpers over nit_terminal
  nit_layout.erl      Flexbox-style layout engine
  nit_focus.erl       Focus tree traversal
  nit_nav.erl         Table/list navigation with scroll offsets
  nit_tree_nav.erl    Tree widget navigation
  nit_hit.erl         Mouse hit testing
  nit_element.erl     Element trait functions (height, width, children)
  nit_unicode.erl     Unicode display width utilities
include/
  nit_elements.hrl    Public element record definitions
test/                 EUnit test suite
examples/             Demo application
```

## Build and test

```sh
rebar3 compile
rebar3 eunit
```

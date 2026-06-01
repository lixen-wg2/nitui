# Documentation

## Read next

- [Vision and design notes](../nitui.md)
- [Demo guide](../examples/README.md)

## Project structure

```
src/                  Framework runtime
  iso_server.erl      Main gen_server (event loop, rendering, state)
  iso_engine.erl      Shared navigation, pagination, focus, input logic
  iso_tty.erl         Low-level terminal I/O via prim_tty
  iso_input.erl       ANSI input parser (keys, mouse SGR)
  iso_render.erl      Element tree → screen buffer renderer
  iso_screen.erl      Cell-based screen buffer with diffing
  iso_ansi.erl        ANSI escape code helpers
  iso_layout.erl      Flexbox-style layout engine
  iso_focus.erl       Focus tree traversal
  iso_nav.erl         Table/list navigation with scroll offsets
  iso_tree_nav.erl    Tree widget navigation
  iso_hit.erl         Mouse hit testing
  iso_element.erl     Element trait functions (height, width, children)
  iso_unicode.erl     Unicode display width utilities
include/
  iso_elements.hrl    Public element record definitions
test/                 EUnit test suite
examples/             Demo application
```

## Build and test

```sh
rebar3 compile
rebar3 eunit
```

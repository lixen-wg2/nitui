# Overview

NitUI is a Nitrogen-inspired terminal UI framework for Erlang/OTP. An
application describes its screen as a tree of element records; the framework
owns the terminal, parses input, resolves layout, manages focus and repaints
only the cells that changed.

<img src="assets/nitui-demo.gif" alt="NitUI terminal demo" width="900">

## What it does for you

- **Declarative views** — `view(State)` returns an element tree
  (`#vbox{}`, `#panel{}`, `#table{}`, `#tabs{}`, `#tree{}`, `#input{}`, ...).
- **Retained mode** — the framework keeps the tree, diffs frames and merges
  widget state (selection, scroll, sort) across rebuilds.
- **Input handling** — ANSI key and SGR mouse parsing, including wheel
  scrolling, drag selection and bracketed paste.
- **Two-level focus** — Tab moves between containers, arrows move inside them.
- **Terminal ownership** — raw mode, alternate screen, cursor and mouse modes,
  SIGWINCH resize and a synchronous cleanup path.
- **Unicode aware** — display-width based layout for wide characters and emoji.

## The shape of an application

```erlang
-module(hello).
-behaviour(nit_callback).

-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{count => 0}}.

view(#{count := Count}) ->
    #vbox{children = [
        #text{content = io_lib:format("Count: ~B", [Count])},
        #button{id = inc, label = "Increment", focusable = true},
        #status_bar{items = [{"Enter", "Increment"}, {"Q", "Quit"}]}
    ]}.

handle_event({click, inc, _Handler}, #{count := Count} = State) ->
    {noreply, State#{count => Count + 1}};
handle_event({event, {char, $q}}, State) ->
    {stop, normal, State};
handle_event(_Event, State) ->
    {unhandled, State}.
```

Three callbacks carry the whole contract: `init/1` builds state, `view/1` is a
pure function from state to elements, and `handle_event/2` turns events into
new state or navigation. See [`nit_callback`](nit_callback.html) for the
behaviour and [Your first application](first-app.html) for a full walkthrough.

## Installation

Add NitUI to `rebar.config`:

```erlang
{deps, [nitui]}.
```

Then add it to your application's dependency list in `*.app.src` so OTP starts
`nitui` — and therefore the terminal and input drivers — before your UI:

```erlang
{applications, [kernel, stdlib, nitui]}.
```

## Requirements

- Erlang/OTP 29 or later. NitUI uses `prim_tty` for raw terminal access and
  `io_ansi` for terminal control; there is no fallback path.
- A terminal emulator with ANSI styling and SGR (1006) mouse reporting.
- A VM that owns the terminal: start it with `-noinput` and do not take over the
  reader of an existing Erlang shell. See
  [Terminal lifecycle](terminal-lifecycle.html).

## Where to go next

| Page | Contents |
|------|----------|
| [Quick start](quick-start.html) | Run the demo and create a project |
| [Your first application](first-app.html) | Build a UI callback module step by step |
| [Elements](elements.html) | Every element record and its fields |
| [Layout and sizing](layout.html) | `auto`, `fill`, flex heights, borders |
| [Focus and navigation](focus-and-navigation.html) | Containers, children, mouse focus |
| [Events](events.html) | Every event and every handler response |
| [Views and overlays](views-and-overlays.html) | push/pop/switch, modals, fullscreen |
| [Tables](tables.html) | Sorting, virtual scrolling, clickable cells |
| [Text and clipboard](text-and-clipboard.html) | `#text_view{}`, OSC 52 copying |
| [Live updates](live-updates.html) | `tick`, async updates, injected events |
| [Styling](styling.html) | Style maps, colours, widget palettes |
| [Key bindings](key-bindings.html) | What the framework consumes and forwards |
| [Configuration](configuration.html) | Application environment keys |
| [Terminal lifecycle](terminal-lifecycle.html) | Startup, cleanup, resize, crashes |
| [Architecture](architecture.html) | Modules, event cycle, design notes |
| [Demo application](demo.html) | The bundled Observer-style demo |

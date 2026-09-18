# Events

`handle_event/2` is the optional third callback of `nit_callback`. If a module
does not export it, all events are ignored and the UI is static.

```erlang
handle_event(Event, State) -> Result.
```

## Widget events

These are emitted by the framework when a widget is used.

| Event | Emitted when |
|-------|--------------|
| `{click, Id, Handler}` | Enter, Space or a mouse click on a focusable enabled `#button{}` |
| `{submit, Id, Value, Handler}` | Enter in a focused `#input{}` |
| `{input, Id, Value}` | The value of a focused `#input{}` changed |
| `{list_select, Id, Index, Item}` | The selection of a `#list{}` moved (`Index` is 0-based) |
| `{tab_change, Id, TabId}` | The active tab of a `#tabs{}` changed |
| `{table_select, Id, RowIndex, RowData}` | The selected row of a `#table{}` moved (1-based) |
| `{table_activate, Id, RowIndex, RowData}` | Enter, or a click configured to activate |
| `{table_cell_click, Id, RowIndex, ColumnId, RowData}` | A cell in `clickable_columns` was clicked |
| `{table_header_click, Id, ColumnId}` | A column header was clicked |
| `{tree_select, Id, NodeId}` | The selected tree node moved |
| `{tree_activate, Id, NodeId}` | Enter on a tree node |

`Handler` is whatever was put in the element's `on_click` / `on_submit` field —
`{Module, Function}`, a `fun()`, or `undefined`. The framework passes it back
rather than calling it, so the handler stays a plain value in your state.

## Lifecycle and raw events

| Event | Meaning |
|-------|---------|
| `tick` | Sent once per second for live refreshes. See [Live updates](live-updates.html) |
| `quit` | Ctrl+C was pressed. Return `{stop, Reason, State}` to exit, anything else to ignore it |
| `{event, RawEvent}` | A key or mouse event the framework did not consume |

Raw events arrive wrapped in `{event, _}`. The inner term comes from
`nit_input`:

- `{char, Char}` — printable character
- `{ctrl, Char}` — control combination, e.g. `{ctrl, $r}`
- `{key, up | down | left | right | home | 'end' | page_up | page_down | btab | f1..f12}`
- `{key, {shift, Key}}` for the shifted variants
- `enter`, `tab`, `escape`, `backspace`, `delete`
- `{mouse, click | motion | release, left | middle | right | release, Col, Row}` —
  `Col`/`Row` are 1-based
- `{mouse, scroll, up | down | left | right, Col, Row}`
- `{paste, start | 'end'}` — bracketed paste markers

Events injected with `nit_server:send_event/2` are wrapped the same way, so an
application-sent `refresh` arrives as `{event, refresh}`.

See [Key bindings](key-bindings.html) for exactly which keys the framework
consumes before forwarding.

## Return values

| Result | Effect |
|--------|--------|
| `{noreply, State}` | Store the state; rebuild and repaint if it changed |
| `{unhandled, State}` | Same, but marks the event as not consumed |
| `{stop, Reason, State}` | Terminate the UI server with `Reason` |
| `{modal, Modal, State}` | Show an element record as a modal overlay |
| `{switch, Module, Args}` | Replace the current view, discarding the stack entry |
| `{push, Module, Args}` / `{push, Module, Args, State}` | Push a new view, saving the current one |
| `pop` | Return to the saved view |
| `{fullscreen, Id, State}` | Render one element as the whole screen |
| `{toggle_fullscreen, Id, State}` | Enter or leave fullscreen for that element |
| `{exit_fullscreen, State}` | Leave fullscreen |

There is no separate "update state" result: returning `noreply` with changed
state is what triggers a rebuild. `{unhandled, State}` differs only in intent —
it records the event for debugging and signals that the framework may apply its
own default for it.

Navigation results are described in
[Views and overlays](views-and-overlays.html).

## Declarative shortcuts

`nit_shortcuts:handle/3` matches an event against a binding list and returns
`nomatch` if nothing applies:

```erlang
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"r",               fun(S) -> {noreply, refresh(S)} end},
        {"ctrl+l",          fun(S) -> {noreply, S} end},
        {["q", escape],     {stop, normal}},
        {{key, page_down},  fun(S) -> {noreply, next_page(S)} end}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

Bindings are tried in order. A spec is:

- a one-character string or binary, matched case-insensitively (`"q"`)
- a name: `"enter"`, `"tab"`, `"shift+tab"`, `"esc"`/`"escape"`,
  `"backspace"`, `"up"`, `"down"`, `"left"`, `"right"`, `"home"`, `"end"`,
  `"pageup"`, `"pagedown"`, `"f1"`..`"f12"`, `"ctrl+<char>"`
- the corresponding atom or tuple (`escape`, `{key, page_up}`, `{ctrl, $c}`)
- a list of any of the above, matching if any element matches

An action is either a `fun((State) -> Result)` or a literal result. The
shorthands `stop` and `{stop, Reason}` expand to `{stop, normal, State}` and
`{stop, Reason, State}`.

`nit_shortcuts:matches/2` exposes the same matching for a single spec, and
`nit_shortcuts:parse/1` normalises an event or spec into its canonical form.

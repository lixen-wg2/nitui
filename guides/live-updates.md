# Live updates

A NitUI view is rebuilt whenever state changes. There are three ways state
changes without user input: the periodic tick, an external state update, and an
injected event.

## The tick

The server sends itself `refresh_tick` every second and calls
`handle_event(tick, State)` if the callback module exports `handle_event/2`.

```erlang
handle_event(tick, State) ->
    {noreply, State#{stats => collect_stats()}};
```

Only `{noreply, NewState}` is honoured for `tick`; any other return value —
including a crash — leaves the state unchanged, and the next tick is scheduled
regardless. Keep tick work cheap and non-blocking: it runs in the UI process,
so a slow collector stalls input handling.

After the handler returns, the framework rebuilds the view and repaints only
the cells that changed.

A one-second cadence is fixed. For a different rate, keep your own timer in the
application and push updates in with `nit_server:update/2` or
`nit_server:send_event/2`.

## Updating state from outside

```erlang
nit_server:update(my_tui_ui, fun(State) -> State#{rows => NewRows} end).
```

`update/2` is a cast that applies the function to the user state inside the UI
process and re-renders. Use it from a collector process, a `gen_server`
handling subscriptions, or a REPL.

`nit_server:get_state/1` is the matching call, mostly useful in tests.

## Injecting events

```erlang
nit_server:send_event(my_tui_ui, {rows, NewRows}).
```

The event is routed through the same path as unconsumed input, so it arrives
wrapped:

```erlang
handle_event({event, {rows, NewRows}}, State) ->
    {noreply, State#{rows => NewRows}};
```

Injected events may return any of the results in [Events](events.html), so a
background process can push, pop, open a modal or stop the UI.

## Widget state is preserved

Rebuilds — from ticks, updates, injected events, and resizes — merge the
previous widget state into the new tree by element `id`:

- table selection, scroll offset, sort column and direction
- list selection and offset
- tree selection, expansion and offset
- scroll container offset
- input value, cursor position and selection
- text view cursor, selection, offset and copy status

Merging recurses through nested containers, tabs and scroll areas. Anonymous
layout records (a `#vbox{}` with no id, for instance) do not shadow the
activation of a focused named table inside them.

This is why per-tick refreshes do not fight the user: a table the user has
scrolled and sorted keeps its position while the rows underneath change.

Two ways to take control back:

- `#table.controlled = true` — the application owns selection, scroll and sort
  on every rebuild.
- `#table.row_keys` — keep merged selection, but anchor it to row identity
  rather than row position, so refreshes and reordering follow the row.

See [Tables](tables.html).

## Async data patterns

Do the slow work elsewhere and hand finished data to the UI:

```erlang
%% In a collector process
Rows = expensive_query(),
nit_server:update(my_tui_ui, fun(S) -> S#{rows => Rows, loading => false} end).
```

```erlang
%% In the view
view(#{loading := true}) ->
    #vbox{children = [#text{content = "Loading..."}]};
view(#{rows := Rows}) ->
    #vbox{children = [table(Rows)]}.
```

`view/1` must stay a pure function of state — do not query the world from it.
On the initial render after `init/1` and after a `push`, the framework calls
`view/1` twice: the first pass seeds the tree context used by
`nitui:selected_item/1`, the second produces the rendered tree. Side effects
placed in `view/1` fire twice on those entry points.

## Cursor blink and resize

A separate 500 ms timer blinks the text cursor while an `#input{}` or
`#text_view{}` is focused; it does not call into application code.

Terminal resizes arrive as SIGWINCH, reset the frame buffer, reconcile
selections against the new bounds and repaint in full. Applications do not
handle resize explicitly. See
[Terminal lifecycle](terminal-lifecycle.html).

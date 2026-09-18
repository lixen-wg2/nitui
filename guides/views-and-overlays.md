# Views and overlays

One `nit_server` process shows one view at a time. A view is a callback module
plus its state. The framework keeps a navigation stack so views can be pushed
and popped, and can additionally show a modal overlay or expand one element to
fill the screen.

## Switching views

```erlang
handle_event({click, settings_btn, _}, _State) ->
    {switch, settings_view, #{}}.
```

`{switch, Module, Args}` replaces the current view: `Module:init(Args)` runs,
the stack is untouched, and the previous state is discarded. Use it for
top-level screens the user moves between freely.

## Pushing and popping

```erlang
handle_event({table_activate, procs, _Row, [Pid | _]}, State) ->
    {push, process_detail, #{pid => Pid}, State}.
```

`{push, Module, Args, State}` stores the current callback module, state,
element tree and focus on the stack, then initialises `Module`. The four-tuple
form stores the state you pass, so any pending update is not lost;
`{push, Module, Args}` keeps the state as it already is.

Returning `pop` from the pushed view restores the saved entry exactly —
including the selected table row and focus position — and repaints the screen.
`pop` on an empty stack is a no-op, so bind it defensively:

```erlang
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [{["escape", "q"], pop}]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

## Modals

A modal is an ordinary `#modal{}` record shown on top of the current view:

```erlang
handle_event({click, delete_btn, _}, State) ->
    Modal = #modal{
        title = "Confirm",
        border = double,
        children = [
            #text{content = "Delete the selected entry?"},
            #hbox{spacing = 2, children = [
                #button{id = confirm_yes, label = "Yes", focusable = true},
                #button{id = confirm_no,  label = "No",  focusable = true}
            ]}
        ]
    },
    {modal, Modal, State}.
```

While a modal is active:

- Focus navigation and input routing are scoped to the modal subtree. The
  framework picks an initial focus inside it, preferring the first focusable
  container and its first focusable child, and falling back to the modal's
  direct children.
- `Escape` closes the modal. Page keys are swallowed. Character shortcuts do
  **not** leak through to the view underneath, so a modal cannot accidentally
  trigger the screen's `q`/`p`/`n` bindings.
- Clicks inside the modal act normally; the events (`{click, confirm_yes, _}`
  and so on) reach the same `handle_event/2`.

The modal is framework state, not part of the tree returned by `view/1`, so
returning `{noreply, State}` from a modal button leaves it open. Close it with
`nit_server:close_modal/1`, or let the user press `Escape`:

```erlang
handle_event({click, confirm_yes, _}, State) ->
    ok = nit_server:close_modal(self()),
    {noreply, delete_selected(State)};
handle_event({click, confirm_no, _}, State) ->
    ok = nit_server:close_modal(self()),
    {noreply, State}.
```

`nit_server:set_modal/2` and `close_modal/1` are casts, so they also work from
outside the UI process:

```erlang
nit_server:set_modal(my_tui_ui, Modal),
nit_server:close_modal(my_tui_ui).
```

## Fullscreen

`{fullscreen, Id, State}` renders the element with that id as the entire
screen, stretched to `width = fill, height = fill` at the origin. The rest of
the view is hidden but not destroyed: the framework saves the base tree and the
focus position.

```erlang
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"f", fun(S) -> {toggle_fullscreen, main_table, S} end}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

- `{toggle_fullscreen, Id, State}` enters fullscreen, or leaves it when that id
  is already fullscreen.
- `{exit_fullscreen, State}` leaves it; so does `Escape`.
- Rebuilds while fullscreen re-extract the element from the new tree, so ticks
  and async updates keep working. If the id disappears from the tree, the
  framework leaves fullscreen.

Containers, tables, lists, trees, tabs, scrolls, text, text views, buttons,
inputs and headers can all be made fullscreen.

## Ending the application

`{stop, Reason, State}` terminates the `nit_server` process with that reason.
Because a UI that the user quit should not be restarted into a terminal being
torn down, register the child with `restart => temporary`:

```erlang
#{id => my_tui_ui,
  start => {nit_server, start_link, [{local, my_tui_ui}, my_tui_view, #{}]},
  restart => temporary,
  shutdown => 5000,
  type => worker,
  modules => [nit_server, my_tui_view]}
```

Normal shutdown runs terminal cleanup. See
[Terminal lifecycle](terminal-lifecycle.html).

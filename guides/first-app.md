# Your first application

This guide builds a two-screen application: a table of ETS tables, and a
detail screen reached by activating a row. It assumes the project layout from
[Quick start](quick-start.html).

## 1. State and the element tree

`init/1` returns the initial state. `view/1` is a pure function from that state
to an element tree.

```erlang
-module(tables_view).
-behaviour(nit_callback).

-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{filter => <<>>}}.

view(#{filter := Filter}) ->
    Rows = rows(Filter),
    #vbox{children = [
        #header{title = "ETS", subtitle = atom_to_list(node()),
                items = [{"Tables", nit_format:commas(length(Rows))}]},
        #table{
            id = ets_table,
            height = fill,
            focusable = true,
            sortable = true,
            columns = [
                #table_col{id = name,   header = "Name",    width = fill},
                #table_col{id = size,   header = "Objects", width = 12, align = right},
                #table_col{id = memory, header = "Memory",  width = 12, align = right}
            ],
            rows = Rows
        },
        #status_bar{items = [{"Enter", "Details"}, {"Tab", "Focus"}, {"Q", "Quit"}]}
    ]}.
```

Two details matter here:

- `focusable = true` is opt-in. An element without it never receives focus and
  never emits selection or activation events.
- `height = fill` lets the table consume the space left over by the header and
  status bar. See [Layout and sizing](layout.html).

## 2. Handling events

`handle_event/2` receives framework-level events and returns either new state or
a navigation instruction.

```erlang
handle_event({table_activate, ets_table, _RowIdx, [Name | _]}, State) ->
    {push, table_detail, #{name => Name}, State};
handle_event({table_select, ets_table, _RowIdx, _RowData}, State) ->
    {noreply, State};
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

`{push, Module, Args, State}` stores the current view — state, tree and focus —
and starts `Module` as a new screen. Returning `pop` restores it exactly.
`{unhandled, State}` tells the framework the event was not consumed, so it may
apply its own default handling. See [Events](events.html).

## 3. The detail screen

A pushed view is an ordinary callback module. It receives the `Args` map in
`init/1`.

```erlang
-module(table_detail).
-behaviour(nit_callback).

-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(#{name := Name}) ->
    {ok, #{name => Name, info => ets:info(Name)}}.

view(#{name := Name, info := Info}) ->
    #vbox{children = [
        #header{title = io_lib:format("~p", [Name])},
        #box{border = single, title = "Info", height = fill, children = [
            #text{content = io_lib:format("~p", [Info]), wrap = true}
        ]},
        #status_bar{items = [{"Esc", "Back"}]}
    ]}.

handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [{["escape", "q"], pop}]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

## 4. Refreshing live data

The framework sends `tick` to `handle_event/2` once per second. Recompute
whatever your view reads from and return `{noreply, NewState}`:

```erlang
handle_event(tick, State) ->
    {noreply, State#{info => ets:info(maps:get(name, State))}};
```

Selection, scroll offset and sort order survive the rebuild — the framework
merges the previous widget state into the new tree, keyed by element `id`. Set
`#table.controlled = true` if the application wants to own those instead. See
[Live updates](live-updates.html).

## 5. Adding an input field

```erlang
#input{id = filter, placeholder = "Filter...", focusable = true, width = 30}
```

Typing into a focused `#input{}` emits `{input, filter, Value}`; Enter emits
`{submit, filter, Value, Handler}`:

```erlang
handle_event({input, filter, Value}, State) ->
    {noreply, State#{filter => Value}};
```

Store the value in your state and let `view/1` read it back. Do not try to
mutate the element record in place — the tree is rebuilt from state.

## Next steps

- [Elements](elements.html) — the full record reference
- [Focus and navigation](focus-and-navigation.html) — how Tab and arrows resolve
- [Views and overlays](views-and-overlays.html) — modals and fullscreen

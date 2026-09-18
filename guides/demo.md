# Demo application

The repository ships an Observer-style demo in `examples/` that exercises most
of the framework. It is the fastest way to see the widgets, and a working
reference for launcher and supervisor setup.

<img src="assets/nitui-demo.gif" alt="NitUI terminal demo" width="900">

## Run it

```sh
git clone https://github.com/lixen-wg2/nitui.git
cd nitui/examples
./run.sh
```

`run.sh` compiles the framework and the demo, starts `erl -noinput`, monitors
the registered `demo_ui` process and restores the terminal from a shell `trap`
if the VM dies badly. See [Terminal lifecycle](terminal-lifecycle.html).

Press `Q` to quit. `Tab` cycles focus, arrow keys navigate inside widgets, and
the status bar on each screen lists its shortcuts.

## Screens

| Module | What it demonstrates |
|--------|----------------------|
| `demo_home` | `#header{}`, `#stat_row{}`, `#progress_bar{}`, `#sparkline{}`, buttons, `#spacer{}` pushing the status bar down, live `tick` refresh of real VM statistics |
| `demo_processes` | A sortable, focusable `#table{height = fill}` of live processes with `activate_on_reclick`, pushing a detail view on activation |
| `process_detail` | A pushed view initialised from `Args`, returning `pop` |
| `demo_network` | Network counters with sparklines |
| `demo_ets` | ETS table browser |
| `demo_tree` | `#tree{}` with expansion, selection and reveal |
| `demo_virtual` | Virtual scrolling `#table{}` driven by a `row_provider` |
| `demo_widgets` | Widget showcase: lists, tabs, scroll containers, inputs, buttons, modals |

## Structure worth copying

`demo.app.src` lists `nitui` as a dependency so OTP starts the terminal
drivers first, and registers the UI process name:

```erlang
{registered, [demo_ui]},
{applications, [kernel, stdlib, nitui]}
```

`demo_sup` starts the UI as a temporary child under a `one_for_one` supervisor:

```erlang
init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
    Children = [
        #{
            id => demo_home,
            start => {nit_server, start_link, [{local, demo_ui}, demo_home, #{}]},
            restart => temporary,
            shutdown => 5000,
            type => worker,
            modules => [nit_server, demo_home]
        }
    ],
    {ok, {SupFlags, Children}}.
```

Every screen ends its `handle_event/2` with a shortcut table and falls through
to `{unhandled, State}`:

```erlang
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {"p", fun(_) -> {switch, demo_processes, #{}} end},
        {"n", fun(_) -> {switch, demo_network, #{}} end},
        {["q", escape], {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

Note the two navigation styles side by side: `switch` between peer screens
(Home, Processes, Network) and `push`/`pop` for drill-down (a process row to
its detail view).

`demo_home` also shows the `tick` pattern — collect fresh statistics, keep a
bounded history for the sparklines, and return `{noreply, NewState}`:

```erlang
handle_event(tick, State) ->
    NewStats = collect_stats(),
    ...
    {noreply, maps:merge(NewStats, #{reductions_history => NewRedHist, ...})}.
```

## Tests

The EUnit suite in `test/` covers the same ground the demo does visually —
state merging, selection, rendering, table activation, hit testing, unicode
widths and terminal cleanup:

```sh
rebar3 eunit
```

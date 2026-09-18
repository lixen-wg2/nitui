# Quick start

## Prerequisites

- Erlang/OTP 29 or later (`erl -noshell -eval 'io:format("~s~n",[erlang:system_info(otp_release)]),halt().'`)
- rebar3
- A terminal emulator with ANSI styling and SGR mouse reporting

## Run the bundled demo

The repository ships an Observer-style demo that exercises most widgets.

```sh
git clone https://github.com/lixen-wg2/nitui.git
cd nitui
rebar3 compile
cd examples
./run.sh
```

`run.sh` compiles the framework and the demo, starts a VM with `-noinput`, and
waits for the UI process to exit. Press `Q` to quit; `Tab` cycles focus and the
status bar lists the per-screen shortcuts. See [Demo
application](demo.html) for the screen list.

## Create a project

### 1. Generate a release-style application

```sh
rebar3 new app my_tui
cd my_tui
```

### 2. Add the dependency

`rebar.config`:

```erlang
{deps, [nitui]}.
```

`src/my_tui.app.src` — listing `nitui` under `applications` makes OTP start the
terminal and input drivers before your supervisor:

```erlang
{applications, [kernel, stdlib, nitui]}.
```

### 3. Write the view module

`src/my_tui_view.erl`:

```erlang
-module(my_tui_view).
-behaviour(nit_callback).

-include_lib("nitui/include/nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{ticks => 0}}.

view(#{ticks := Ticks}) ->
    #vbox{children = [
        #header{title = "My TUI", subtitle = atom_to_list(node())},
        #panel{children = [
            #text{content = io_lib:format("Ticks: ~B", [Ticks])}
        ]},
        #spacer{},
        #status_bar{items = [{"Q", "Quit"}]}
    ]}.

handle_event(tick, #{ticks := Ticks} = State) ->
    {noreply, State#{ticks => Ticks + 1}};
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [{["q", escape], {stop, normal}}]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.
```

### 4. Start the UI from your supervisor

`src/my_tui_sup.erl`:

```erlang
init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
    Children = [
        #{
            id => my_tui_ui,
            start => {nit_server, start_link, [{local, my_tui_ui}, my_tui_view, #{}]},
            restart => temporary,
            shutdown => 5000,
            type => worker,
            modules => [nit_server, my_tui_view]
        }
    ],
    {ok, {SupFlags, Children}}.
```

`restart => temporary` matters: a UI that stops because the user quit should
not be restarted into a terminal that is being torn down.

### 5. Run it

NitUI needs the terminal to itself, so start a dedicated VM with `-noinput` and
block until the UI process exits:

```sh
rebar3 compile
erl -noinput -pa _build/default/lib/*/ebin -eval "application:ensure_all_started(my_tui), Pid = whereis(my_tui_ui), Ref = erlang:monitor(process, Pid), receive {'DOWN', Ref, process, _, _} -> ok end, halt()."
```

Use a double-quoted shell string so the `'DOWN'` atom keeps its quotes. For
anything beyond a one-liner, copy `examples/run.sh`, which wraps the same
command and restores the terminal from a shell `trap` as a last resort.

> #### Do not start a UI in a shell VM {: .warning}
>
> `rebar3 shell` and an interactive `erl` own the terminal reader themselves.
> Starting a NitUI server there fights the shell for input. Use a separate
> `-noinput` VM as shown above.

## Next steps

- [Your first application](first-app.html) — build a real screen step by step
- [Elements](elements.html) — the widget catalogue
- [Events](events.html) — what `handle_event/2` receives and may return

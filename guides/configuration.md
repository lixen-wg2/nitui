# Configuration

NitUI is configured in three places: the application environment, the
`nit_server` child spec, and the VM flags of the process that owns the
terminal.

## Application environment

`nitui` ships with an empty `env`. The only keys it reads are the clipboard
settings:

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `clipboard_enabled` | `boolean()` | `true` | Only `true` enables copying; any other value yields `{error, disabled}` |
| `clipboard_max_bytes` | `pos_integer()` | `65536` | Raw UTF-8 bytes before base64; valid range `1..1048576`, outside it copying returns `{error, unavailable}` |
| `clipboard_transport` | `direct \| tmux` | `direct` | `tmux` wraps OSC 52 in DCS passthrough |

```erlang
%% sys.config
[
 {nitui, [
     {clipboard_enabled, true},
     {clipboard_max_bytes, 262144},
     {clipboard_transport, tmux}
 ]}
].
```

Oversized text is refused, never truncated. `tmux` passthrough must be
supported and enabled in the multiplexer itself; NitUI never detects it. See
[Text and clipboard](text-and-clipboard.html).

## Starting the UI server

`nit_server` takes the callback module and the argument passed to `init/1`:

| Function | Use |
|----------|-----|
| `nit_server:start_link(Module)` | `init(#{})`, unnamed process |
| `nit_server:start_link(Module, InitArg)` | Unnamed process |
| `nit_server:start_link(Name, Module, InitArg)` | `Name` is `{local, Atom}` or `{global, Term}` |

A registered name is worth having: `nit_server:update/2`,
`send_event/2`, `set_modal/2` and `close_modal/1` all address the server, and a
launcher script needs it to monitor the UI process.

```erlang
#{id => my_tui_ui,
  start => {nit_server, start_link, [{local, my_tui_ui}, my_tui_view, #{}]},
  restart => temporary,
  shutdown => 5000,
  type => worker,
  modules => [nit_server, my_tui_view]}
```

`restart => temporary` is the right default: the user quitting is not a
failure, and restarting into a terminal that is being restored produces a
corrupt screen.

## Dependency declaration

List `nitui` under `applications` in your `*.app.src` so OTP starts the TTY
owner and the input reader before your supervisor:

```erlang
{applications, [kernel, stdlib, nitui]}.
```

`nitui:start/0` and `nitui:stop/0` are thin wrappers over
`application:ensure_all_started(nitui)` and `application:stop(nitui)` for
scripts and tests.

## VM flags

The terminal must belong to the VM running the UI.

| Flag | Why |
|------|-----|
| `-noinput` | Disables the Erlang shell's reader while keeping the TTY attached |
| `-noshell` | For a fully standalone launcher that wants no shell at all |
| `+Bc` | Makes Ctrl+C reach the application instead of the BEAM break handler |

`-noinput` is the flag that matters. `-noshell` detaches from the TTY in a way
that is only appropriate for a launcher that never expects shell interaction.

```sh
erl -noinput -pa _build/default/lib/*/ebin -eval "application:ensure_all_started(my_tui), Pid = whereis(my_tui_ui), Ref = erlang:monitor(process, Pid), receive {'DOWN', Ref, process, _, _} -> ok end, halt()."
```

> #### `rebar3 shell` will not work {: .warning}
>
> An interactive shell owns the terminal reader. Starting a `nit_server` there
> makes the shell and the UI compete for input. Use a separate `-noinput` VM.

## Terminal detection

`nit_sup` starts `nit_tty` and `nit_input` only when a usable terminal is
present: `prim_tty:isatty(stdin)` and `prim_tty:isatty(stdout)` must be true, and `TERM`
must be set to something other than `""` or `dumb`. Without a TTY the
application still starts, with no terminal children — which is what makes
headless tests possible.

`nit_terminal:capabilities/0` reports what was detected:

```erlang
#{ansi => true, color => true, term_columns => 120, term_lines => 40}
```

`color` is `false` when `NO_COLOR` is set in the environment.

## Requirements

- Erlang/OTP 29 or later. `minimum_otp_vsn` is declared in `nitui.app.src`;
  NitUI uses `prim_tty` and `io_ansi` with no fallback path.
- A terminal emulator with ANSI styling and SGR (1006) mouse reporting.

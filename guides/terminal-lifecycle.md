# Terminal lifecycle

NitUI takes exclusive ownership of the terminal. Understanding when it grabs
and releases that ownership is the difference between a clean exit and a shell
left in raw mode.

## Startup

Starting the `nitui` application starts `nit_sup`, which starts two workers —
but only when a usable terminal is present. `nit_sup` requires
`prim_tty:isatty(stdin)` and `prim_tty:isatty(stdout)` to be true, and `TERM` to be set
to something other than `""` or `dumb`. Without those, no terminal children are
started and the application still comes up, which is what allows headless
tests.

`nit_tty:init/1` then, in order:

1. Initialises `prim_tty` in raw mode and takes the reader handle.
2. Registers `nit_sighandler` with `erl_signal_server` for SIGWINCH (Unix only).
3. Writes the entry sequence: alternate screen, keypad transmit mode, cursor
   hide, mouse mode (1002 + 1006), clear.
4. Starts reading input, which `nit_input` parses and forwards to the UI
   server.

## Rendering

`nit_server` renders through `nit_render` into a `nit_screen` cell buffer,
diffs it against the previous frame, and writes only the changed cells via
`nit_tty:write/1` — an asynchronous cast.

`nit_tty:write_control/1` is the synchronous path used for control frames such
as OSC 52 clipboard writes. It never logs and never falls back to stdio, and an
acknowledgement confirms terminal output, not that the terminal acted on it.

## Resize

SIGWINCH arrives at `nit_sighandler`, which notifies `nit_tty`, which sends
`{resize, Cols, Rows}` to the UI server. The server resets the diff buffer,
reconciles widget selections against the new bounds, clears the screen and
repaints in full. Applications do not handle resize.

The BEAM also delivers `sigwinch` to supervisors in the process tree, and OTP
logs a warning for unexpected messages. `nitui_app` installs a primary logger
filter (`nit_sigwinch_filter`) that drops exactly those reports and removes it
again on application stop.

## Cleanup

`nit_tty:cleanup/0` is the single exit path. It synchronously:

1. Stops input reading.
2. Drains the reset sequence — reset attributes, mouse mode off, keypad mode
   off, cursor show, alternate screen off — waiting for the writer to
   acknowledge.
3. Restores cooked terminal mode, even if the writer died or timed out.

It returns `ok` or `{error, cleanup_failed}`, is idempotent — repeated calls
return the first result without writing again — and **ends that terminal
session**: later writes are ignored.

`nit_server:terminate/2` calls it on normal shutdown, after cancelling its
timers. So a `{stop, normal, State}` from `handle_event/2` restores the
terminal without any further work from the application.

## Launcher responsibilities

A launcher owns the VM, so it owns the fallback path:

```sh
#!/bin/bash
cleanup() {
    printf '\e[?1006l\e[?1000l'   # mouse off
    printf '\e[?25h'              # cursor on
    printf '\e[?1049l'            # leave alternate screen
    printf '\e[0m'                # reset attributes
}
trap cleanup EXIT

erl -noinput -pa _build/default/lib/*/ebin -eval "application:ensure_all_started(my_tui), Pid = whereis(my_tui_ui), Ref = erlang:monitor(process, Pid), receive {'DOWN', Ref, process, _, _} -> ok end, halt()."
```

Two things are going on:

- Monitoring the named UI process is how the script knows the user quit.
  Without it the VM exits immediately.
- The `trap` is a last resort for the case where the VM dies so hard that
  `nit_tty:cleanup/0` never runs.

A launcher that supervises the UI itself can also call `nit_tty:cleanup/0`
explicitly after a UI crash, before stopping its own `nitui` application.

`examples/run.sh` is a working version of the above.

## VM flags

| Flag | Why |
|------|-----|
| `-noinput` | Disables the shell reader while keeping the TTY attached |
| `-noshell` | For a standalone launcher that wants no shell at all |
| `+Bc` | Ctrl+C reaches the application instead of the BEAM break handler |

> #### Never run a UI in a shell VM {: .warning}
>
> `rebar3 shell` and interactive `erl` own the terminal reader. A `nit_server`
> started there competes with the shell for every keystroke. Use a dedicated
> `-noinput` VM.

## Failure modes

| Situation | Result |
|-----------|--------|
| UI process crashes | Supervisor terminates it; `terminate/2` still runs cleanup |
| VM killed with SIGKILL | No cleanup runs; the shell `trap` restores the terminal |
| Ctrl+C in raw mode | Delivered as `{ctrl, $c}`, surfaced as the `quit` event |
| `nit_tty` restarted | `nit_sup` uses `one_for_all`, so `nit_input` restarts with it |
| No TTY available | No terminal children start; the UI has nowhere to render |

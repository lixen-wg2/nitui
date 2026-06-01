#!/bin/bash
cd "$(dirname "$0")"

# Cleanup function to restore terminal state
cleanup() {
    # Disable mouse tracking (SGR extended mode)
    printf '\e[?1006l\e[?1000l'
    # Show cursor
    printf '\e[?25h'
    # Exit alternate screen
    printf '\e[?1049l'
    # Reset attributes
    printf '\e[0m'
}

# Set trap to run cleanup on exit (catches Ctrl+C, etc.)
trap cleanup EXIT

# Use -noinput instead of -noshell to keep TTY available for the TUI
# -noshell detaches from the TTY, but -noinput just disables the Erlang shell
(cd .. && rebar3 compile) && rebar3 compile && erl -noinput -pa ../_build/default/lib/*/ebin -pa _build/default/lib/*/ebin -eval "application:ensure_all_started(demo), UiPid = whereis(demo_ui), Ref = erlang:monitor(process, UiPid), receive {'DOWN', Ref, process, _, _} -> ok end"

%%%-------------------------------------------------------------------
%%% Demo application for NitUI TUI framework.
%%%-------------------------------------------------------------------
-module(demo_app).
-moduledoc "Demo application for the NitUI TUI framework.".

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    demo_sup:start_link().

stop(_State) ->
    ok.


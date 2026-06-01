%%%-------------------------------------------------------------------
%%% @doc NitUI top-level supervisor.
%%%
%%% Supervises:
%%% - iso_tty: TTY owner process (prim_tty state, cleanup)
%%% - iso_input: Input reader and parser
%%%
%%% Uses one_for_all strategy since all components depend on each other.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% @doc Start the supervisor.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc Supervisor init callback.
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 5
    },

    %% Only start TTY components if a TTY is available.
    %% This allows the web demo to work without a real terminal.
    Children = case has_tty() of
        true ->
            [
                #{
                    id => iso_tty,
                    start => {iso_tty, start_link, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [iso_tty]
                },
                #{
                    id => iso_input,
                    start => {iso_input, start_link, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [iso_input]
                }
            ];
        false ->
            %% No TTY - running in web mode or headless
            []
    end,

    {ok, {SupFlags, Children}}.

%% Check if we have a TTY available.
%% Do not call prim_tty:init/1 here. Initializing in the supervisor process
%% makes it receive terminal signal messages such as {Ref, {signal, sigwinch}}.
has_tty() ->
    try
        ok = prim_tty:load(),
        supported_term() andalso
            prim_tty:isatty(stdin) =:= true andalso
            prim_tty:isatty(stdout) =:= true
    catch
        _:_ -> false
    end.

supported_term() ->
    case os:getenv("TERM") of
        false -> false;
        "" -> false;
        "dumb" -> false;
        _ -> true
    end.

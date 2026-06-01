%%%-------------------------------------------------------------------
%%% @doc TTY owner process for NitUI.
%%%
%%% Manages the terminal state using OTP 28's prim_tty module.
%%% Responsibilities:
%%% - Initialize raw mode terminal
%%% - Enter alternate screen buffer
%%% - Hide cursor
%%% - Ensure cleanup on exit (restore terminal state)
%%% - Provide write interface for rendering
%%% - Forward input data to iso_input for parsing
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tty).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0, cleanup/0]).
-export([write/1, clear/0, get_size/0]).
-export([set_resize_target/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    tty_state :: prim_tty:state() | undefined,
    reader_ref :: reference() | undefined,
    resize_target :: pid() | undefined  %% Process to notify on resize
}).

%% ANSI escape sequences
-define(ENTER_ALT_SCREEN, <<"\e[?1049h">>).
-define(EXIT_ALT_SCREEN, <<"\e[?1049l">>).
-define(HIDE_CURSOR, <<"\e[?25l">>).
-define(SHOW_CURSOR, <<"\e[?25h">>).
-define(RESET_ATTRS, <<"\e[0m">>).
-define(CLEAR_SCREEN, <<"\e[2J\e[H">>).
%% Mouse tracking (button-event mode + SGR extended coordinates)
-define(ENABLE_MOUSE, <<"\e[?1002h\e[?1006h">>).
-define(DISABLE_MOUSE, <<"\e[?1006l\e[?1002l">>).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Cleanup terminal state (disable mouse, show cursor, exit alt screen).
%% This is called before shutdown to restore the terminal.
-spec cleanup() -> ok.
cleanup() ->
    gen_server:call(?MODULE, cleanup).

%% @doc Write raw data to the terminal.
-spec write(iodata()) -> ok.
write(Data) ->
    gen_server:cast(?MODULE, {write, Data}),
    ok.

%% @doc Clear the screen.
-spec clear() -> ok.
clear() ->
    write(?CLEAR_SCREEN).

%% @doc Get terminal size as {Cols, Rows}.
-spec get_size() -> {ok, {pos_integer(), pos_integer()}} | {error, term()}.
get_size() ->
    gen_server:call(?MODULE, get_size).

%% @doc Set the process to notify on terminal resize.
%% The target will receive {resize, Cols, Rows} messages.
-spec set_resize_target(pid()) -> ok.
set_resize_target(Pid) ->
    gen_server:cast(?MODULE, {set_resize_target, Pid}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    process_flag(trap_exit, true),
    case init_tty() of
        {ok, TtyState} ->
            %% Get the reader reference from prim_tty handles
            #{read := ReaderRef} = prim_tty:handles(TtyState),
            %% Register signal handler for SIGWINCH (terminal resize)
            case os:type() of
                {unix, _} ->
                    ok = gen_event:add_handler(
                           erl_signal_server, iso_sighandler,
                           #{parent => self()});
                _ ->
                    ok
            end,
            %% Enter alternate screen, hide cursor, enable mouse
            do_write(TtyState, [?ENTER_ALT_SCREEN, ?HIDE_CURSOR, ?ENABLE_MOUSE, ?CLEAR_SCREEN]),
            %% Start reading input
            prim_tty:read(TtyState),
            {ok, #state{tty_state = TtyState, reader_ref = ReaderRef}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(get_size, _From, State = #state{tty_state = TtyState}) ->
    Result = prim_tty:window_size(TtyState),
    {reply, Result, State};

handle_call(cleanup, _From, State = #state{tty_state = TtyState}) ->
    cleanup_tty(TtyState),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({set_resize_target, Pid}, State) ->
    {noreply, State#state{resize_target = Pid}};
handle_cast({write, Data}, State = #state{tty_state = TtyState}) ->
    do_write(TtyState, Data),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Handle SIGWINCH from prim_tty - terminal was resized.
handle_info({ReaderRef, {signal, sigwinch}},
            State = #state{reader_ref = ReaderRef}) ->
    handle_resize_signal(State);

%% Handle SIGWINCH from erl_signal_server - terminal was resized.
handle_info({signal, sigwinch}, State) ->
    handle_resize_signal(State);

%% Handle input data from prim_tty reader - forward to iso_input
handle_info({ReaderRef, {data, Data}}, State = #state{reader_ref = ReaderRef, tty_state = TtyState}) ->
    %% Forward raw data to iso_input for parsing
    iso_input:handle_data(Data),
    %% Request more data
    prim_tty:read(TtyState),
    {noreply, State};

handle_info({ReaderRef, eof}, State = #state{reader_ref = ReaderRef}) ->
    %% Terminal closed
    {stop, normal, State};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

%% Handle raw sigwinch atom (delivered by BEAM runtime in some OTP versions)
handle_info(sigwinch, State) ->
    handle_info({signal, sigwinch}, State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{tty_state = TtyState}) ->
    %% Remove signal handler
    catch gen_event:delete_handler(erl_signal_server, iso_sighandler, []),
    cleanup_tty(TtyState),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

init_tty() ->
    try
        ok = prim_tty:load(),
        TtyState = prim_tty:init(#{input => raw, output => raw}),
        {ok, TtyState}
    catch
        error:enotsup ->
            {error, no_tty_available};
        Class:Reason:Stack ->
            {error, {Class, Reason, Stack}}
    end.

handle_resize_signal(State = #state{tty_state = TtyState, resize_target = Target}) ->
    NewTtyState = handle_tty_signal(TtyState, sigwinch),
    notify_resize(Target, NewTtyState),
    catch prim_tty:read(NewTtyState),
    {noreply, State#state{tty_state = NewTtyState}}.

handle_tty_signal(TtyState, Signal) ->
    try prim_tty:handle_signal(TtyState, Signal) of
        NewTtyState -> NewTtyState
    catch
        _:_ -> TtyState
    end.

notify_resize(undefined, _TtyState) ->
    ok;
notify_resize(Pid, TtyState) when is_pid(Pid) ->
    case catch prim_tty:window_size(TtyState) of
        {ok, {Cols, Rows}} when Cols > 0, Rows > 0 ->
            Pid ! {resize, Cols, Rows};
        {ok, {Cols, Rows}} ->
            Pid ! {resize, max(1, Cols), max(1, Rows)};
        _ ->
            ok
    end.

do_write(undefined, _Data) ->
    ok;
do_write(TtyState, Data) ->
    case tty_output(Data) of
        {ok, Output} ->
            safe_prim_write(TtyState, Output);
        error ->
            logger:warning("iso_tty: dropping malformed write payload (~p bytes)",
                           [iolist_size_safe(Data)]),
            ok
    end.

tty_output(Data) ->
    case unicode:characters_to_binary(Data) of
        Bin when is_binary(Bin) ->
            {ok, Bin};
        _ ->
            try iolist_to_binary(Data) of
                Bin -> {ok, Bin}
            catch
                _:_ -> error
            end
    end.

safe_prim_write(TtyState, Output) ->
    try prim_tty:write(TtyState, Output) of
        ok -> ok;
        {ok, _MonitorRef} -> ok;
        Other ->
            logger:warning("iso_tty: prim_tty:write returned ~p", [Other]),
            safe_io_write(Output)
    catch
        Class:Reason ->
            logger:warning("iso_tty: prim_tty:write crashed ~p:~p", [Class, Reason]),
            safe_io_write(Output)
    end.

safe_io_write(Output) ->
    try io:put_chars(user, Output) of
        ok -> ok;
        Other ->
            logger:warning("iso_tty: io:put_chars returned ~p", [Other]),
            ok
    catch
        Class:Reason ->
            logger:warning("iso_tty: io:put_chars crashed ~p:~p", [Class, Reason]),
            ok
    end.

iolist_size_safe(Data) ->
    try iolist_size(Data)
    catch _:_ -> unknown
    end.

cleanup_tty(undefined) ->
    ok;
cleanup_tty(TtyState) ->
    %% Restore terminal state
    do_write(TtyState, [
        ?RESET_ATTRS,
        ?DISABLE_MOUSE,
        ?SHOW_CURSOR,
        ?EXIT_ALT_SCREEN
    ]).

%%%-------------------------------------------------------------------
%%% @doc TTY owner process for NitUI.
%%%
%%% Manages the terminal state using OTP 29's prim_tty and io_ansi modules.
%%% Responsibilities:
%%% - Initialize raw mode terminal
%%% - Enter alternate screen buffer
%%% - Hide cursor
%%% - Ensure cleanup on exit (restore terminal state)
%%% - Provide write interface for rendering
%%% - Forward input data to nit_input for parsing
%%% @end
%%%-------------------------------------------------------------------
-module(nit_tty).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0, cleanup/0]).
-export([write/1, write_control/1, clear/0, get_size/0]).
-export([set_resize_target/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([format_status/1]).

-ifdef(TEST).
-export([state_for_test/2, cleanup_for_test/3, write_control_for_test/4]).
-endif.

%% Leave time for reader shutdown and mode restoration within the API timeout.
-define(CLEANUP_DRAIN_TIMEOUT, 1000).
-define(CLEANUP_CALL_TIMEOUT, 5000).
-define(CONTROL_WRITE_TIMEOUT, 1000).
-define(CONTROL_CALL_TIMEOUT, 5000).

-record(state, {
    tty_state :: prim_tty:state() | undefined,
    reader_ref :: reference() | undefined,
    resize_target :: pid() | undefined,  %% Process to notify on resize
    cleanup_result = ok :: ok | {error, cleanup_failed}
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Stop input, drain terminal resets, and restore cooked terminal mode.
%% Repeated calls return the first result without writing or restarting input.
%% Failures are deliberately sanitized: no terminal state or output escapes.
-spec cleanup() -> ok | {error, cleanup_failed}.
cleanup() ->
    try gen_server:call(?MODULE, cleanup, ?CLEANUP_CALL_TIMEOUT) of
        ok -> ok;
        _ -> {error, cleanup_failed}
    catch
        _:_ -> {error, cleanup_failed}
    end.

%% @doc Write raw data to the terminal.
-spec write(iodata()) -> ok.
write(Data) ->
    gen_server:cast(?MODULE, {write, Data}),
    ok.

%% @doc Synchronously submit one complete control frame to the active terminal.
%% Unlike rendering writes, this never logs or falls back to stdio. A writer
%% acknowledgement confirms terminal output, not acceptance of a control code.
%% Failures are sanitized and never retried (a device may have written bytes).
-spec write_control(binary()) -> ok | {error, unavailable | write_failed}.
write_control(Data) when is_binary(Data) ->
    Deadline = erlang:monotonic_time(millisecond) + ?CONTROL_CALL_TIMEOUT,
    try gen_server:call(?MODULE, {write_control, Data, Deadline}, ?CONTROL_CALL_TIMEOUT) of
        ok -> ok;
        {error, unavailable} -> {error, unavailable};
        _ -> {error, write_failed}
    catch
        exit:{noproc, _} -> {error, unavailable};
        exit:{normal, _} -> {error, unavailable};
        exit:{shutdown, _} -> {error, unavailable};
        exit:{{shutdown, _}, _} -> {error, unavailable};
        _:_ -> {error, write_failed}
    end;
write_control(_Data) ->
    {error, write_failed}.

%% @doc Clear the screen.
-spec clear() -> ok.
clear() ->
    write(nit_terminal:clear()).

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
                           erl_signal_server, nit_sighandler,
                           #{parent => self()});
                _ ->
                    ok
            end,
            %% Enter alternate screen, hide cursor, enable mouse/input modes
            do_write(TtyState, [
                nit_terminal:alternate_screen(),
                nit_terminal:keypad_transmit_mode(),
                nit_terminal:cursor_hide(),
                nit_terminal:mouse_mode(),
                nit_terminal:clear()
            ]),
            %% Start reading input
            prim_tty:read(TtyState),
            {ok, #state{tty_state = TtyState, reader_ref = ReaderRef}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(get_size, _From, State = #state{tty_state = undefined}) ->
    {reply, {error, terminal_closed}, State};
handle_call(get_size, _From, State = #state{tty_state = TtyState}) ->
    Result = prim_tty:window_size(TtyState),
    {reply, Result, State};

handle_call(cleanup, _From, State) ->
    {Result, CleanState} = cleanup_state(State),
    {reply, Result, CleanState};

handle_call({write_control, Data, Deadline}, _From, State) when is_integer(Deadline) ->
    %% Drop expired queued requests rather than writing after the caller timed out.
    Timeout = min(?CONTROL_WRITE_TIMEOUT, Deadline - erlang:monotonic_time(millisecond)),
    Result = control_write(State, Data,
                           #{handles => fun prim_tty:handles/1,
                             write => fun prim_tty:write/3}, Timeout),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State = #state{tty_state = undefined}) ->
    {noreply, State};
handle_cast({set_resize_target, Pid}, State) ->
    {noreply, State#state{resize_target = Pid}};
handle_cast({write, Data}, State = #state{tty_state = TtyState}) ->
    do_write(TtyState, Data),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Reader data, EOF and resize signals may already be queued at cleanup time.
%% In particular, never issue another read or reinitialize the cleared TTY.
handle_info(_Info, State = #state{tty_state = undefined}) ->
    {noreply, State};

%% Handle SIGWINCH from prim_tty - terminal was resized.
handle_info({ReaderRef, {signal, sigwinch}},
            State = #state{reader_ref = ReaderRef}) ->
    handle_resize_signal(State);

%% Handle SIGWINCH from erl_signal_server - terminal was resized.
handle_info({signal, sigwinch}, State) ->
    handle_resize_signal(State);

%% Handle input data from prim_tty reader - forward to nit_input
handle_info({ReaderRef, {data, Data}}, State = #state{reader_ref = ReaderRef, tty_state = TtyState}) ->
    %% Forward raw data to nit_input for parsing
    nit_input:handle_data(Data),
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

terminate(_Reason, State) ->
    %% Remove signal handler
    try gen_event:delete_handler(erl_signal_server, nit_sighandler, [])
    catch _:_ -> ok
    end,
    _ = cleanup_state(State),
    ok.

%% Control frames must not become payload-bearing crash or status reports.
-spec format_status(gen_server:format_status()) -> gen_server:format_status().
format_status(Status) ->
    maps:map(fun
        (state, State) -> State;
        (_, Value) -> redact_control(Value)
    end, Status).

%%====================================================================
%% Internal functions
%%====================================================================

redact_control({write_control, _Data, _Deadline}) ->
    {write_control, redacted};
redact_control(Tuple) when is_tuple(Tuple) ->
    list_to_tuple([redact_control(Value) || Value <- tuple_to_list(Tuple)]);
redact_control([Head | Tail]) ->
    [redact_control(Head) | redact_control(Tail)];
redact_control(Map) when is_map(Map) ->
    maps:map(fun(_, Value) -> redact_control(Value) end, Map);
redact_control(Value) ->
    Value.

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
    try prim_tty:read(NewTtyState)
    catch _:_ -> ok
    end,
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
    case safe_window_size(TtyState) of
        {ok, {Cols, Rows}} when Cols > 0, Rows > 0 ->
            Pid ! {resize, Cols, Rows};
        {ok, {Cols, Rows}} ->
            Pid ! {resize, max(1, Cols), max(1, Rows)};
        _ ->
            ok
    end.

safe_window_size(TtyState) ->
    try prim_tty:window_size(TtyState)
    catch _:_ -> error
    end.

do_write(undefined, _Data) ->
    ok;
do_write(TtyState, Data) ->
    case tty_output(Data) of
        {ok, Output} ->
            safe_prim_write(TtyState, Output);
        error ->
            logger:warning("nit_tty: dropping malformed write payload (~p bytes)",
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
        _ ->
            logger:warning("nit_tty: prim_tty:write failed"),
            safe_io_write(Output)
    catch
        _:_ ->
            logger:warning("nit_tty: prim_tty:write failed"),
            safe_io_write(Output)
    end.

safe_io_write(Output) ->
    try io:put_chars(user, Output) of
        ok -> ok;
        _ ->
            logger:warning("nit_tty: io:put_chars failed"),
            ok
    catch
        _:_ ->
            logger:warning("nit_tty: io:put_chars failed"),
            ok
    end.

iolist_size_safe(Data) ->
    try iolist_size(Data)
    catch _:_ -> unknown
    end.

control_write(#state{tty_state = undefined}, _Data, _Ops, _Timeout) ->
    {error, unavailable};
control_write(#state{tty_state = TtyState}, Data, Ops, Timeout)
        when is_binary(Data), Timeout > 0 ->
    try
        #{handles := Handles, write := Write} = Ops,
        #{write := WriterRef} = Handles(TtyState),
        Owner = self(),
        Request = make_ref(),
        %% A per-write recipient prevents late acknowledgements from a timed-out
        %% write from completing a later control write or cleanup drain.
        ReplyTo = spawn(fun() -> control_ack(Owner, Request, WriterRef) end),
        try
            {ok, Monitor} = Write(TtyState, Data, ReplyTo),
            try
                receive
                    {Request, ok} -> ok;
                    {'DOWN', Monitor, process, _, _} -> {error, write_failed}
                after Timeout ->
                    {error, write_failed}
                end
            after
                erlang:demonitor(Monitor, [flush])
            end
        after
            exit(ReplyTo, kill),
            receive {Request, ok} -> ok after 0 -> ok end
        end
    catch
        _:_ -> {error, write_failed}
    end;
control_write(_State, _Data, _Ops, _Timeout) ->
    {error, write_failed}.

control_ack(Owner, Request, WriterRef) ->
    Monitor = erlang:monitor(process, Owner),
    receive
        {WriterRef, ok} -> Owner ! {Request, ok};
        {'DOWN', Monitor, process, Owner, _} -> ok
    end.

cleanup_state(State) ->
    cleanup_state(State, #{reader_stop => fun prim_tty:reader_stop/1,
                           handles => fun prim_tty:handles/1,
                           write => fun prim_tty:write/3,
                           reinit => fun prim_tty:reinit/2},
                  ?CLEANUP_DRAIN_TIMEOUT).

cleanup_state(State = #state{tty_state = undefined, cleanup_result = Result},
              _Ops, _Timeout) ->
    {Result, State};
cleanup_state(State = #state{tty_state = TtyState}, Ops, Timeout) ->
    Result = cleanup_tty(TtyState, Ops, Timeout),
    {Result, State#state{tty_state = undefined, reader_ref = undefined,
                         resize_target = undefined, cleanup_result = Result}}.

cleanup_tty(TtyState, Ops = #{reader_stop := Stop, reinit := Reinit}, Timeout) ->
    {Stopped, StopResult} = try Stop(TtyState) of
        NewTtyState -> {NewTtyState, ok}
    catch
        _:_ -> {TtyState, {error, cleanup_failed}}
    end,
    %% Keep this in the owner process: its earlier writes precede the reset.
    %% Do not fall back to asynchronous write/2 or group-leader output here.
    DrainResult = cleanup_attempt(fun() -> drain_reset(Stopped, Ops, Timeout) end),
    %% Always release raw mode, even if the writer died or failed to acknowledge.
    ModeResult = cleanup_attempt(fun() ->
        _ = Reinit(Stopped, #{input => disabled, output => cooked}),
        ok
    end),
    case {StopResult, DrainResult, ModeResult} of
        {ok, ok, ok} -> ok;
        _ -> {error, cleanup_failed}
    end.

cleanup_attempt(Fun) ->
    try Fun() of
        ok -> ok;
        _ -> {error, cleanup_failed}
    catch
        _:_ -> {error, cleanup_failed}
    end.

drain_reset(TtyState, #{handles := Handles, write := Write}, Timeout) ->
    Output = unicode:characters_to_binary([
        nit_terminal:reset(),
        nit_terminal:mouse_mode_off(),
        nit_terminal:keypad_transmit_mode_off(),
        nit_terminal:cursor_show(),
        nit_terminal:alternate_screen_off()
    ]),
    #{write := WriterRef} = Handles(TtyState),
    {ok, Monitor} = Write(TtyState, Output, self()),
    try
        receive
            {WriterRef, ok} -> ok;
            {'DOWN', Monitor, process, _, _} -> {error, cleanup_failed}
        after Timeout ->
            {error, cleanup_failed}
        end
    after
        erlang:demonitor(Monitor, [flush])
    end.

-ifdef(TEST).
%% Exercise the real cleanup and callbacks with fake TTY operations, without
%% starting a terminal or duplicating the private state record in tests.
state_for_test(TtyState, ReaderRef) ->
    #state{tty_state = TtyState, reader_ref = ReaderRef}.

cleanup_for_test(State, Ops, Timeout) ->
    cleanup_state(State, Ops, Timeout).

write_control_for_test(State, Data, Ops, Timeout) ->
    control_write(State, Data, Ops, Timeout).
-endif.

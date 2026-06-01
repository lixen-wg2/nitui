%%%-------------------------------------------------------------------
%%% @doc Input driver for NitUI.
%%%
%%% Receives raw input from nit_tty and parses ANSI escape sequences into
%%% clean event messages. Forwards parsed events to nit_server.
%%%
%%% Parsed events:
%%% - {key, up | down | left | right | home | 'end' | page_up | page_down}
%%% - {key, {shift, left | right | home | 'end'}}
%%% - {char, Char} - Regular character
%%% - {ctrl, Char} - Control key (e.g., {ctrl, $c})
%%% - {mouse, scroll, up | down | left | right, Col, Row}
%%% - enter, tab, backspace, escape, delete
%%% @end
%%%-------------------------------------------------------------------
-module(nit_input).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([handle_data/1, set_target/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    buffer = <<>> :: binary(),
    target = undefined :: pid() | undefined
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

%% @doc Handle raw input data from nit_tty.
-spec handle_data(binary()) -> ok.
handle_data(Data) ->
    gen_server:cast(?MODULE, {data, Data}).

%% @doc Set the target process to receive input events.
-spec set_target(pid()) -> ok.
set_target(Pid) ->
    gen_server:cast(?MODULE, {set_target, Pid}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({data, Data}, State = #state{buffer = Buffer, target = Target}) ->
    NewBuffer = <<Buffer/binary, Data/binary>>,
    {Events, RemainingBuffer} = parse_input(NewBuffer),
    lists:foreach(fun(E) -> send_event(E, Target) end, Events),
    {noreply, State#state{buffer = RemainingBuffer}};

handle_cast({set_target, Pid}, State) ->
    {noreply, State#state{target = Pid}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

send_event(Event, Target) ->
    %% Send to target process
    case Target of
        undefined -> ok;
        Pid when is_pid(Pid) -> Pid ! {input, Event}
    end.

%% Parse input buffer into events
-spec parse_input(binary()) -> {[term()], binary()}.
parse_input(Buffer) ->
    parse_input(Buffer, []).

parse_input(<<>>, Acc) ->
    {lists:reverse(Acc), <<>>};

%% Escape sequences
parse_input(<<"\e[1;2C", Rest/binary>>, Acc) -> parse_input(Rest, [{key, {shift, right}} | Acc]);
parse_input(<<"\e[1;2D", Rest/binary>>, Acc) -> parse_input(Rest, [{key, {shift, left}} | Acc]);
parse_input(<<"\e[1;2H", Rest/binary>>, Acc) -> parse_input(Rest, [{key, {shift, home}} | Acc]);
parse_input(<<"\e[1;2F", Rest/binary>>, Acc) -> parse_input(Rest, [{key, {shift, 'end'}} | Acc]);
parse_input(<<"\e[A", Rest/binary>>, Acc) -> parse_input(Rest, [{key, up} | Acc]);
parse_input(<<"\e[B", Rest/binary>>, Acc) -> parse_input(Rest, [{key, down} | Acc]);
parse_input(<<"\e[C", Rest/binary>>, Acc) -> parse_input(Rest, [{key, right} | Acc]);
parse_input(<<"\e[D", Rest/binary>>, Acc) -> parse_input(Rest, [{key, left} | Acc]);
parse_input(<<"\e[H", Rest/binary>>, Acc) -> parse_input(Rest, [{key, home} | Acc]);
parse_input(<<"\e[F", Rest/binary>>, Acc) -> parse_input(Rest, [{key, 'end'} | Acc]);
parse_input(<<"\e[5~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, page_up} | Acc]);
parse_input(<<"\e[6~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, page_down} | Acc]);
parse_input(<<"\e[3~", Rest/binary>>, Acc) -> parse_input(Rest, [delete | Acc]);
parse_input(<<"\e[Z", Rest/binary>>, Acc) -> parse_input(Rest, [{key, btab} | Acc]);  %% Shift+Tab

%% Function keys (F1-F12)
parse_input(<<"\eOP", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f1} | Acc]);
parse_input(<<"\eOQ", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f2} | Acc]);
parse_input(<<"\eOR", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f3} | Acc]);
parse_input(<<"\eOS", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f4} | Acc]);
parse_input(<<"\e[15~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f5} | Acc]);
parse_input(<<"\e[17~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f6} | Acc]);
parse_input(<<"\e[18~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f7} | Acc]);
parse_input(<<"\e[19~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f8} | Acc]);
parse_input(<<"\e[20~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f9} | Acc]);
parse_input(<<"\e[21~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f10} | Acc]);
parse_input(<<"\e[23~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f11} | Acc]);
parse_input(<<"\e[24~", Rest/binary>>, Acc) -> parse_input(Rest, [{key, f12} | Acc]);

%% SGR Mouse events: \e[<button;col;rowM (press) or \e[<button;col;rowm (release)
parse_input(<<"\e[<", Rest/binary>>, Acc) ->
    case parse_mouse_sgr(Rest) of
        {ok, Event, Remaining} ->
            parse_input(Remaining, [Event | Acc]);
        incomplete ->
            {lists:reverse(Acc), <<"\e[<", Rest/binary>>}
    end;

%% Unknown or incomplete SS3 sequence (\eO...)
parse_input(<<"\eO", Rest/binary>> = Buffer, Acc) ->
    case classify_ss3(Rest) of
        incomplete ->
            {lists:reverse(Acc), Buffer};
        {complete, Remaining} ->
            %% Unknown SS3 sequence - consume and ignore it.
            parse_input(Remaining, Acc)
    end;

%% Unknown or incomplete CSI sequence (\e[...)
parse_input(<<"\e[", Rest/binary>> = Buffer, Acc) ->
    case classify_csi(Rest) of
        incomplete ->
            {lists:reverse(Acc), Buffer};
        {complete, Remaining} ->
            %% Unknown CSI sequence - consume and ignore it.
            parse_input(Remaining, Acc)
    end;

%% Standalone Escape key (no [ following, so not an escape sequence)
parse_input(<<"\e", Rest/binary>>, Acc) when byte_size(Rest) == 0 ->
    %% Just ESC alone - send it as escape event
    {lists:reverse([escape | Acc]), <<>>};
parse_input(<<"\e", C, Rest/binary>>, Acc) when C =/= $[ ->
    %% ESC followed by non-[ character - send escape and continue parsing
    parse_input(<<C, Rest/binary>>, [escape | Acc]);

%% Special keys (must come before control characters to avoid Tab being Ctrl+I)
parse_input(<<9, Rest/binary>>, Acc) -> parse_input(Rest, [tab | Acc]);
parse_input(<<13, Rest/binary>>, Acc) -> parse_input(Rest, [enter | Acc]);
parse_input(<<127, Rest/binary>>, Acc) -> parse_input(Rest, [backspace | Acc]);

%% Control characters
parse_input(<<0, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $@} | Acc]);  %% Ctrl+@/Space
parse_input(<<C, Rest/binary>>, Acc) when C >= 1, C =< 26 ->
    parse_input(Rest, [{ctrl, C + $a - 1} | Acc]);
parse_input(<<28, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $\\} | Acc]);
parse_input(<<29, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $]} | Acc]);
parse_input(<<30, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $^} | Acc]);
parse_input(<<31, Rest/binary>>, Acc) -> parse_input(Rest, [{ctrl, $_} | Acc]);

%% Regular characters (including UTF-8)
parse_input(<<C/utf8, Rest/binary>>, Acc) when C >= 32 ->
    parse_input(Rest, [{char, C} | Acc]);

%% Unknown byte - skip
parse_input(<<_, Rest/binary>>, Acc) ->
    parse_input(Rest, Acc).

%% Parse SGR mouse format: button;col;rowM or button;col;rowm
%% Button: 0=left, 1=middle, 2=right, 32+=motion, 64+=scroll
%% Scroll directions: 64=up, 65=down, 66=left, 67=right
parse_mouse_sgr(Data) ->
    parse_sgr_params(Data, []).

%% Accumulator-based scan: collect semicolon-separated numbers, then match terminator
parse_sgr_params(<<>>, _Acc) ->
    incomplete;
parse_sgr_params(<<$;, Rest/binary>>, Acc) ->
    parse_sgr_params(Rest, [0 | Acc]);
parse_sgr_params(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    parse_sgr_number(Rest, C - $0, Acc);
parse_sgr_params(<<$M, Rest/binary>>, Acc) ->
    finish_sgr(lists:reverse(Acc), true, Rest);
parse_sgr_params(<<$m, Rest/binary>>, Acc) ->
    finish_sgr(lists:reverse(Acc), false, Rest);
parse_sgr_params(_, _Acc) ->
    incomplete.

parse_sgr_number(<<>>, _Num, _Acc) ->
    incomplete;
parse_sgr_number(<<C, Rest/binary>>, Num, Acc) when C >= $0, C =< $9 ->
    parse_sgr_number(Rest, Num * 10 + (C - $0), Acc);
parse_sgr_number(<<$;, Rest/binary>>, Num, Acc) ->
    parse_sgr_params(Rest, [Num | Acc]);
parse_sgr_number(<<$M, Rest/binary>>, Num, Acc) ->
    finish_sgr(lists:reverse([Num | Acc]), true, Rest);
parse_sgr_number(<<$m, Rest/binary>>, Num, Acc) ->
    finish_sgr(lists:reverse([Num | Acc]), false, Rest);
parse_sgr_number(_, _Num, _Acc) ->
    incomplete.

finish_sgr([Button, Col, Row], IsPress, Rest) ->
    Event = mouse_event(Button, IsPress, Col, Row),
    {ok, Event, Rest};
finish_sgr(_, _, _) ->
    incomplete.

mouse_event(Button, _IsPress, Col, Row) when Button >= 64 ->
    Direction = case Button band 3 of
        0 -> up;
        1 -> down;
        2 -> left;
        3 -> right
    end,
    {mouse, scroll, Direction, Col, Row};
mouse_event(Button, IsPress, Col, Row) ->
    ButtonType = case Button band 3 of
        0 -> left;
        1 -> middle;
        2 -> right;
        3 -> release
    end,
    EventType = if
        Button >= 32 -> motion;
        IsPress -> click;
        true -> release
    end,
    {mouse, EventType, ButtonType, Col, Row}.

classify_ss3(<<>>) ->
    incomplete;
classify_ss3(<<Final, Rest/binary>>) when Final >= 64, Final =< 126 ->
    {complete, Rest};
classify_ss3(_) ->
    incomplete.

classify_csi(<<>>) ->
    incomplete;
classify_csi(<<Final, Rest/binary>>) when Final >= 64, Final =< 126 ->
    {complete, Rest};
classify_csi(<<_, Rest/binary>>) ->
    classify_csi(Rest).

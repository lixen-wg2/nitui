%%%-------------------------------------------------------------------
%%% @doc Demo Processes Page - live list of Erlang processes
%%% @end
%%%-------------------------------------------------------------------
-module(demo_processes).

-behaviour(iso_callback).

-include_lib("nitui/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    Snapshots = snapshot(),
    #vbox{children = [
        #header{
            title = "Processes",
            subtitle = atom_to_list(node()),
            items = [{"Total", iso_format:commas(length(Snapshots))}]
        },
        #stat_row{items = stats(Snapshots)},
        #table{
            id = proc_table,
            height = fill,
            border = single,
            focusable = true,
            sortable = true,
            activate_on_reclick = true,
            columns = [
                #table_col{id = pid,  header = "PID",               width = 14},
                #table_col{id = name, header = "Name/Initial Call", width = 30},
                #table_col{id = reds, header = "Reds",   width = 14, align = right},
                #table_col{id = mem,  header = "Memory", width = 12, align = right},
                #table_col{id = msgq, header = "MsgQ",   width = 6,  align = right}
            ],
            rows = [process_row(S) || S <- Snapshots],
            selected_row = 1
        },
        #status_bar{items = [
            {"H", "Home"},
            {"Enter", "Details"},
            {"Q", "Quit"}
        ]}
    ]}.

handle_event({table_activate, proc_table, _RowIdx, [Pid | _]}, State)
  when is_pid(Pid) ->
    {push, process_detail, #{pid => Pid}, State};
handle_event(Event, State) ->
    case iso_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

%%====================================================================
%% Internal functions
%%====================================================================

snapshot() ->
    lists:filtermap(fun process_snapshot/1, erlang:processes()).

process_snapshot(Pid) ->
    case erlang:process_info(Pid, [registered_name, initial_call,
                                   reductions, memory, message_queue_len,
                                   status]) of
        undefined -> false;
        Info      -> {true, maps:from_list([{pid, Pid} | Info])}
    end.

stats(Snapshots) ->
    {Running, Waiting, MsgQ} = lists:foldl(fun count/2, {0, 0, 0}, Snapshots),
    [{"Running",    iso_format:commas(Running)},
     {"Waiting",    iso_format:commas(Waiting)},
     {"MsgQ Total", iso_format:commas(MsgQ)}].

count(S, {R, W, M}) ->
    Q = maps:get(message_queue_len, S, 0),
    case maps:get(status, S, waiting) of
        running -> {R + 1, W,     M + Q};
        _       -> {R,     W + 1, M + Q}
    end.

process_row(S) ->
    [maps:get(pid, S),
     process_name(S),
     iso_format:commas(maps:get(reductions, S, 0)),
     iso_format:bytes(maps:get(memory, S, 0)),
     maps:get(message_queue_len, S, 0)].

process_name(S) ->
    case maps:get(registered_name, S, []) of
        []   -> format_mfa(maps:get(initial_call, S, undefined));
        Name -> atom_to_list(Name)
    end.

format_mfa({M, F, A}) ->
    lists:flatten(io_lib:format("~ts:~ts/~B",
                                [atom_to_list(M), atom_to_list(F), A]));
format_mfa(_) ->
    "?".

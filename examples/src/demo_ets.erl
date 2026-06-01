%%%-------------------------------------------------------------------
%%% @doc Demo ETS Page - live ETS table inventory.
%%% @end
%%%-------------------------------------------------------------------
-module(demo_ets).

-behaviour(iso_callback).

-include_lib("nitui/include/iso_elements.hrl").

-export([init/1, view/1, handle_event/2]).

init(_Args) ->
    {ok, #{}}.

view(_State) ->
    Snapshots = snapshot(),
    EtsBytes = erlang:memory(ets),
    TotalBytes = erlang:memory(total),
    #vbox{children = [
        #header{
            title = "ETS Tables",
            subtitle = atom_to_list(node()),
            items = [{"Tables", iso_format:commas(length(Snapshots))},
                     {"Memory", iso_format:bytes(EtsBytes)}]
        },
        #text{content = "ETS share of BEAM memory:", style = #{bold => true}},
        #hbox{spacing = 2, children = [
            #progress_bar{value = EtsBytes, max = TotalBytes,
                          width = 40, show_percent = true},
            #text{content = lists:flatten(
                              io_lib:format("(~ts / ~ts)",
                                            [iso_format:bytes(EtsBytes),
                                             iso_format:bytes(TotalBytes)]))}
        ]},
        #stat_row{items = stats(Snapshots)},
        #table{
            id = ets_table,
            height = fill,
            border = single,
            focusable = true,
            sortable = true,
            columns = [
                #table_col{id = name,  header = "Name",       width = 28},
                #table_col{id = type,  header = "Type",       width = 14},
                #table_col{id = prot,  header = "Protection", width = 11},
                #table_col{id = size,  header = "Size",       width = 12, align = right},
                #table_col{id = mem,   header = "Memory",     width = 12, align = right},
                #table_col{id = owner, header = "Owner",      width = 22}
            ],
            rows = [table_row(S) || S <- Snapshots],
            selected_row = 1
        },
        #status_bar{items = [
            {"H", "Home"},
            {"Up/Down", "Select"},
            {"Q", "Quit"}
        ]}
    ]}.

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
    lists:filtermap(fun table_snapshot/1, ets:all()).

table_snapshot(Tab) ->
    case ets:info(Tab) of
        undefined -> false;
        Info      -> {true, maps:from_list([{tab, Tab} | Info])}
    end.

stats(Snapshots) ->
    {Named, Anon, Objects} =
        lists:foldl(fun count/2, {0, 0, 0}, Snapshots),
    [{"Named",   iso_format:commas(Named)},
     {"Unnamed", iso_format:commas(Anon)},
     {"Objects", iso_format:commas(Objects)}].

count(S, {N, A, O}) ->
    Size = maps:get(size, S, 0),
    case maps:get(named_table, S, false) of
        true  -> {N + 1, A,     O + Size};
        false -> {N,     A + 1, O + Size}
    end.

table_row(S) ->
    [table_name(S),
     atom_to_list(maps:get(type, S, set)),
     atom_to_list(maps:get(protection, S, public)),
     iso_format:commas(maps:get(size, S, 0)),
     iso_format:bytes(memory_bytes(S)),
     owner_label(maps:get(owner, S, undefined))].

table_name(S) ->
    case maps:get(named_table, S, false) of
        true  -> atom_to_list(maps:get(name, S, '?'));
        false -> lists:flatten(io_lib:format("~p", [maps:get(tab, S)]))
    end.

memory_bytes(S) ->
    maps:get(memory, S, 0) * erlang:system_info(wordsize).

owner_label(Pid) when is_pid(Pid) ->
    case erlang:process_info(Pid, registered_name) of
        {registered_name, Name} when is_atom(Name) ->
            atom_to_list(Name);
        _ ->
            pid_to_list(Pid)
    end;
owner_label(_) ->
    "?".

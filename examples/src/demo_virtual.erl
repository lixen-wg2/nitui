%% -*- coding: utf-8 -*-
%%%-------------------------------------------------------------------
%%% @doc Demo Virtual Scrolling - Large dataset with 10,000+ rows
%%% 
%%% Demonstrates virtual scrolling where rows are fetched on demand
%%% instead of storing all rows in memory.
%%% @end
%%%-------------------------------------------------------------------
-module(demo_virtual).

-behaviour(nit_callback).

-include("nit_elements.hrl").

-export([init/1, view/1, handle_event/2]).
-export([generate_rows/2]).  %% Exported for row_provider callback

-define(TOTAL_ROWS, 10000).

init(_Args) ->
    {ok, #{selected_row => 1}}.

view(State) ->
    #{selected_row := SelectedRow} = State,
    #vbox{children = [
        %% Header
        #header{
            title = "Virtual Scrolling Demo",
            subtitle = "10,000 Rows - Loaded On Demand",
            items = [{"Total Rows", integer_to_list(?TOTAL_ROWS)}]
        },
        
        %% Stats
        #stat_row{
            items = [
                {"Selected", integer_to_list(SelectedRow)},
                {"Mode", "Virtual"},
                {"Memory", "Minimal"}
            ]
        },

        %% Virtual scrolling table
        #table{
            id = virtual_table,
            height = fill,
            border = single,
            focusable = true,
            columns = [
                #table_col{id = idx, header = "#", width = 8, align = right},
                #table_col{id = name, header = "Name", width = 20},
                #table_col{id = value, header = "Value", width = 15, align = right},
                #table_col{id = status, header = "Status", width = 12},
                #table_col{id = timestamp, header = "Timestamp", width = 20}
            ],
            %% Virtual scrolling: use row_provider instead of rows
            total_rows = ?TOTAL_ROWS,
            row_provider = fun generate_rows/2,
            selected_row = SelectedRow
        },

        %% Status bar
        #status_bar{
            items = [
                {"H", "Home"},
                {"↑/↓", "Navigate"},
                {"Q", "Quit"}
            ]
        }
    ]}.

%% Generate rows on demand - this is called during each render
%% StartIdx is 0-based, Count is the number of rows to fetch
generate_rows(StartIdx, Count) ->
    EndIdx = min(StartIdx + Count - 1, ?TOTAL_ROWS - 1),
    [generate_row(I) || I <- lists:seq(StartIdx, EndIdx)].

generate_row(Idx) ->
    %% Generate deterministic but varied data based on index
    RowNum = Idx + 1,  %% 1-based display
    Name = "Item-" ++ integer_to_list(RowNum),
    Value = RowNum * 17 rem 10000,
    Status = case RowNum rem 4 of
        0 -> "Active";
        1 -> "Pending";
        2 -> "Complete";
        3 -> "Inactive"
    end,
    %% Fake timestamp
    Hour = RowNum rem 24,
    Min = RowNum rem 60,
    Sec = (RowNum * 7) rem 60,
    Timestamp = lists:flatten(
        io_lib:format("2024-01-~2..0B ~2..0B:~2..0B:~2..0B",
                      [(RowNum rem 28) + 1, Hour, Min, Sec])),
    [
        integer_to_list(RowNum),
        Name,
        integer_to_list(Value),
        Status,
        Timestamp
    ].

handle_event({table_select, virtual_table, RowIdx, _RowData}, State) ->
    {noreply, State#{selected_row => RowIdx}};
handle_event(Event, State) ->
    case nit_shortcuts:handle(Event, State, [
        {["h", escape], fun(_) -> {switch, demo_home, #{}} end},
        {"q", {stop, normal}}
    ]) of
        nomatch -> {unhandled, State};
        Result -> Result
    end.

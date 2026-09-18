%%%-------------------------------------------------------------------
%%% NitUI Navigation Utilities
%%%-------------------------------------------------------------------
-module(nit_nav).
-moduledoc """
NitUI Navigation Utilities.

Common functions for navigating scrollable elements (tables, lists).
Used by `nit_server` and `nit_engine`.
""".

-include("nit_elements.hrl").

-export([navigate_table/2, navigate_table/3, navigate_table/4]).
-export([navigate_list/2, navigate_list/3, navigate_list/4]).

%%====================================================================
%% Table Navigation
%%====================================================================

%% Navigate table by 1 row
-spec navigate_table(up | down, #table{}) -> #table{}.
navigate_table(Dir, Table) ->
    navigate_table(Dir, 1, Table).

%% Navigate table by N rows (for scroll wheel)
-spec navigate_table(up | down, pos_integer(), #table{}) -> #table{}.
navigate_table(Dir, Lines, #table{rows = Rows, total_rows = TotalRows} = Table) ->
    NumRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    navigate_table(Dir, Lines, table_visible_height(Table, NumRows), Table).

%% Navigate table by N rows with an explicit visible row count.
-spec navigate_table(up | down, pos_integer(), pos_integer(), #table{}) -> #table{}.
navigate_table(down, Lines, VisibleHeight, #table{rows = Rows, total_rows = TotalRows,
                                                  selected_row = Sel, scroll_offset = Off} = T) ->
    NumRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    case NumRows of
        0 ->
            T#table{selected_row = 0, scroll_offset = 0};
        _ ->
            SafeVisibleH = max(1, VisibleHeight),
            NewSel = min(NumRows, max(0, Sel) + Lines),
            NewOff = table_selection_offset(NewSel, Off, SafeVisibleH),
            MaxOff = max(0, NumRows - SafeVisibleH),
            T#table{selected_row = NewSel, scroll_offset = min(NewOff, MaxOff)}
    end;

navigate_table(up, Lines, VisibleHeight, #table{rows = Rows, total_rows = TotalRows,
                                                selected_row = Sel, scroll_offset = Off} = T) ->
    NumRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    case NumRows of
        0 ->
            T#table{selected_row = 0, scroll_offset = 0};
        _ ->
            SafeVisibleH = max(1, VisibleHeight),
            NewSel = max(1, min(NumRows, max(1, Sel) - Lines)),
            NewOff = table_selection_offset(NewSel, Off, SafeVisibleH),
            MaxOff = max(0, NumRows - SafeVisibleH),
            T#table{selected_row = NewSel, scroll_offset = min(NewOff, MaxOff)}
    end;

navigate_table(_, _Lines, _VisibleHeight, T) -> T.

%% A keyed refresh can move/clear the selection independently of the offset.
%% Bring the new selection into view even when it is more than Lines away.
table_selection_offset(Selected, Offset, VisibleHeight) ->
    if
        Selected > Offset + VisibleHeight -> Selected - VisibleHeight;
        Selected =< Offset -> Selected - 1;
        true -> max(0, Offset)
    end.

%%====================================================================
%% List Navigation
%%====================================================================

%% Navigate list by 1 item
-spec navigate_list(up | down, #list{}) -> #list{}.
navigate_list(Dir, List) ->
    navigate_list(Dir, 1, List).

%% Navigate list by N items (for scroll wheel)
-spec navigate_list(up | down, pos_integer(), #list{}) -> #list{}.
navigate_list(Dir, Lines, #list{items = Items, height = H} = List) ->
    navigate_list(Dir, Lines, list_visible_height(H, length(Items)), List).

%% Navigate list by N items with an explicit visible item count.
-spec navigate_list(up | down, pos_integer(), pos_integer(), #list{}) -> #list{}.
navigate_list(down, Lines, VisibleHeight, #list{items = Items, selected = Sel,
                                                offset = Off} = L) ->
    NumItems = length(Items),
    case NumItems of
        0 ->
            L#list{selected = 0, offset = 0};
        _ ->
            SafeVisibleH = max(1, VisibleHeight),
            NewSel = min(NumItems - 1, max(0, Sel) + Lines),
            NewOff = if NewSel >= Off + SafeVisibleH -> Off + Lines; true -> Off end,
            %% Clamp scroll offset to valid range
            MaxOff = max(0, NumItems - SafeVisibleH),
            L#list{selected = NewSel, offset = min(NewOff, MaxOff)}
    end;

navigate_list(up, Lines, VisibleHeight, #list{items = Items, selected = Sel,
                                              offset = Off} = L) ->
    NumItems = length(Items),
    case NumItems of
        0 ->
            L#list{selected = 0, offset = 0};
        _ ->
            SafeVisibleH = max(1, VisibleHeight),
            NewSel = max(0, min(NumItems - 1, Sel) - Lines),
            NewOff = if NewSel < Off -> max(0, Off - Lines); true -> Off end,
            MaxOff = max(0, NumItems - SafeVisibleH),
            L#list{selected = NewSel, offset = min(NewOff, MaxOff)}
    end;

navigate_list(_, _Lines, _VisibleHeight, L) -> L.

table_visible_height(#table{height = auto}, NumRows) ->
    max(1, NumRows);
table_visible_height(#table{height = fill}, NumRows) ->
    max(1, NumRows);
table_visible_height(#table{height = H} = Table, _NumRows) ->
    max(1, H - nit_el_table:overhead(Table)).

list_visible_height(auto, NumItems) ->
    max(1, NumItems);
list_visible_height(fill, NumItems) ->
    max(1, NumItems);
list_visible_height(H, _NumItems) ->
    max(1, H).

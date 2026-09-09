%%%-------------------------------------------------------------------
%%% @doc NitUI Table Element
%%%
%%% Renders a table with columns, rows, selection, and scrolling.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_el_table).

-behaviour(nit_element).

-include("nit_elements.hrl").

-export([render/3, height/2, width/2, fixed_width/1,
         toggle_sort/2, merge_sort_state/2, header_values/1]).
%% Shared geometry for rendering, hit testing, and navigation.
-export([header_height/1, overhead/1, column_widths/3, column_separator_width/1,
         visible_rows/2, clamp_scroll_offset/2]).

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#table{}, #bounds{}, map()) -> iolist().
render(#table{visible = false}, _Bounds, _Opts) ->
    [];
render(#table{} = Table0, Bounds, Opts) ->
    #table{columns = Columns, selected_row = SelectedRow,
              border = Border,
              zebra = Zebra, style = Style, x = X, y = Y, width = W, height = H,
              column_separator = ColumnSeparator} = Table0,
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Focused = maps:get(focused, Opts, false),
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(Style, BaseStyle),
    SelectionStyle = case Focused of
        true -> Table0#table.focused_selected_style;
        false -> Table0#table.selected_style
    end,

    Width = case W of
        auto -> Bounds#bounds.width - X;
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,

    %% Determine total row count (virtual scrolling or static)
    ActualTotalRows = total_rows(Table0),

    Overhead = overhead(Table0),
    Height = case H of
        auto -> min(ActualTotalRows + Overhead, Bounds#bounds.height - Y);
        fill -> max(Overhead + 1, Bounds#bounds.height - Y);
        _ -> H
    end,

    BorderOffset = case Border of none -> 0; _ -> 1 end,
    HeaderOffset2 = header_height(Table0),
    VisibleHeight = max(0, Height - 2 * BorderOffset - HeaderOffset2),

    %% Fetch visible rows (virtual scrolling or static)
    ScrollOffset = clamp_scroll_offset(Table0, VisibleHeight),
    VisibleRows = visible_rows(Table0, VisibleHeight),

    %% For column width calculation, use visible rows (or sample for virtual)
    ColWidths = column_widths(Table0, VisibleRows, Width - 2 * BorderOffset),

    ContentWidth = max(0, Width - 2 * BorderOffset),
    HeaderRow = render_header(Table0, ColWidths, MergedStyle,
                              ActualX, ActualY, BorderOffset, ContentWidth),

    DataRows = render_visible_rows(VisibleRows, Columns, ColWidths, SelectedRow, ScrollOffset,
                                   Zebra, SelectionStyle, MergedStyle, ActualX, ActualY,
                                   BorderOffset, HeaderOffset2, ContentWidth, ColumnSeparator),

    EmptyRows = render_empty_rows(length(VisibleRows), VisibleHeight, MergedStyle,
                                  ActualX, ActualY, BorderOffset, HeaderOffset2, ContentWidth),

    BorderOutput = render_border(Border, MergedStyle, ActualX, ActualY, Width, Height),

    [BorderOutput, HeaderRow, DataRows, EmptyRows].

-spec height(#table{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#table{height = H} = Table, Bounds) ->
    ActualTotalRows = total_rows(Table),
    case H of
        auto -> min(ActualTotalRows + overhead(Table), Bounds#bounds.height);
        fill -> {flex, overhead(Table) + 1};
        _ -> H
    end.

-spec width(#table{}, #bounds{}) -> pos_integer().
width(#table{width = W}, Bounds) ->
    case W of
        auto -> Bounds#bounds.width;
        fill -> Bounds#bounds.width;
        _ -> W
    end.

-spec fixed_width(#table{}) -> auto | pos_integer().
fixed_width(#table{width = auto}) -> auto;
fixed_width(#table{width = fill}) -> auto;
fixed_width(#table{width = W}) -> W.

%%====================================================================
%% Internal
%%====================================================================

render_header(#table{show_header = false}, _ColWidths, _Style, _X, _Y, _BO, _ContentW) -> [];
render_header(#table{columns = Columns, header_style = HeaderStyle,
                      header_separator = HeaderSeparator,
                      column_separator = ColumnSeparator} = Table,
               ColWidths, Style, ActualX, ActualY, BorderOffset, ContentWidth) ->
    HeaderText = pad_line(render_table_row_text(
        header_values(Table), ColWidths, Columns, ColumnSeparator), ContentWidth),
    HeaderY = ActualY + BorderOffset,
    SepY = ActualY + BorderOffset + 1,
    Separator = case HeaderSeparator of
        false -> [];
        true -> [
            nit_ansi:move_to(SepY, ActualX + BorderOffset),
            nit_ansi:style_to_ansi(Style),
            nit_ansi:repeat_bin(<<"─"/utf8>>, ContentWidth),
            nit_ansi:reset_style()
        ]
    end,
    [
        nit_ansi:move_to(HeaderY, ActualX + BorderOffset),
        nit_ansi:style_to_ansi(maps:merge(maps:merge(Style, #{bold => true}), HeaderStyle)),
        HeaderText,
        nit_ansi:reset_style(),
        Separator
    ].

%% Render already-fetched visible rows (works for both static and virtual scrolling)
render_visible_rows(VisibleRows, Columns, ColWidths, SelectedRow, ScrollOffset,
                    Zebra, SelectionStyle, Style, ActualX, ActualY, BorderOffset, HeaderOffset2,
                    ContentWidth, ColumnSeparator) ->
    lists:map(
        fun({RowIdx, RowData}) ->
            AbsRowIdx = ScrollOffset + RowIdx,
            IsSelected = AbsRowIdx =:= SelectedRow,
            RowStyle = if
                IsSelected ->
                    maps:merge(Style, SelectionStyle);
                Zebra andalso (AbsRowIdx rem 2 =:= 1) ->
                    maps:merge(Style, #{dim => true});
                true -> Style
            end,
            RowText = pad_line(render_table_row_text(RowData, ColWidths, Columns, ColumnSeparator), ContentWidth),
            RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx - 1,
            [
                nit_ansi:move_to(RowY, ActualX + BorderOffset),
                nit_ansi:style_to_ansi(RowStyle),
                RowText,
                nit_ansi:reset_style()
            ]
        end,
        lists:zip(lists:seq(1, length(VisibleRows)), VisibleRows)).

render_empty_rows(RenderedRows, VisibleHeight, Style, ActualX, ActualY,
                  BorderOffset, HeaderOffset2, ContentWidth) ->
    BlankLine = blank_line(ContentWidth),
    lists:map(
        fun(RowIdx) ->
            RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx - 1,
            [
                nit_ansi:move_to(RowY, ActualX + BorderOffset),
                nit_ansi:style_to_ansi(Style),
                BlankLine,
                nit_ansi:reset_style()
            ]
        end,
        lists:seq(RenderedRows + 1, VisibleHeight)).

render_border(none, _Style, _X, _Y, _W, _H) -> [];
render_border(Border, Style, ActualX, ActualY, Width, Height) ->
    {TL, TR, BL, BR, HZ, VT} = nit_ansi:border_chars(Border),
    [
        nit_ansi:style_to_ansi(Style),
        nit_ansi:move_to(ActualY, ActualX),
        TL, nit_ansi:repeat_bin(HZ, Width - 2), TR,
        [[nit_ansi:move_to(ActualY + Row, ActualX),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        nit_ansi:move_to(ActualY + Height - 1, ActualX),
        BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
        nit_ansi:reset_style()
    ].

column_widths(#table{columns = Columns} = Table, Rows, AvailableWidth) ->
    WidthSpecs = width_specs(Columns, header_values(Table)),
    ContentWidths0 = initial_content_widths(WidthSpecs),
    ContentWidths = lists:foldl(
        fun(Row, Widths) ->
            update_content_widths(Widths, WidthSpecs, Row)
        end,
        ContentWidths0,
        Rows),
    SeparatorWidth = max(0, length(Columns) - 1) * column_separator_width(Table),
    case lists:any(fun({{fixed, _}, _}) -> true;
                      ({fill, _}) -> true;
                      (_) -> false
                   end, WidthSpecs) of
        true ->
            constrained_column_widths(WidthSpecs, ContentWidths, AvailableWidth - SeparatorWidth);
        false ->
            legacy_column_widths(ContentWidths, SeparatorWidth, AvailableWidth)
    end.

%% Keep the historical scaling (including its minimum width) for legacy specs.
legacy_column_widths(ContentWidths, SeparatorWidth, AvailableWidth) ->
    TotalWidth = lists:sum(ContentWidths) + SeparatorWidth,
    if
        TotalWidth =< AvailableWidth -> ContentWidths;
        true ->
            Scale = AvailableWidth / max(1, TotalWidth),
            [max(3, round(W * Scale)) || W <- ContentWidths]
    end.

constrained_column_widths(WidthSpecs, ContentWidths, ContentBudget) ->
    FixedWidth = lists:sum([W || {{fixed, W}, _} <- WidthSpecs]),
    Budget = max(0, ContentBudget - FixedWidth),
    Preferred = [W || {{Spec, _}, W} <- lists:zip(WidthSpecs, ContentWidths),
                      Spec =:= auto orelse is_integer(Spec)],
    PreferredTotal = lists:sum(Preferred),
    PreferredWidths = share_widths(Preferred, min(Budget, PreferredTotal)),
    FillCount = length([ok || {fill, _} <- WidthSpecs]),
    FillWidths = share_widths(lists:duplicate(FillCount, 1), max(0, Budget - PreferredTotal)),
    %% Fixed widths survive even an impossible budget; pad_line/2 clips output.
    constrained_widths(WidthSpecs, PreferredWidths, FillWidths).

constrained_widths([], [], []) ->
    [];
constrained_widths([{{fixed, W}, _} | Rest], Preferred, Fills) ->
    [W | constrained_widths(Rest, Preferred, Fills)];
constrained_widths([{fill, _} | Rest], Preferred, [W | Fills]) ->
    [W | constrained_widths(Rest, Preferred, Fills)];
constrained_widths([_ | Rest], [W | Preferred], Fills) ->
    [W | constrained_widths(Rest, Preferred, Fills)].

%% Integer apportionment cannot overrun the budget. Give rounding remainders
%% to nonzero weights from left to right, including equal-weight fill columns.
share_widths(Weights, Budget) ->
    case lists:sum(Weights) of
        0 -> Weights;
        Total ->
            Scaled = [W * Budget div Total || W <- Weights],
            {Widths, _} = lists:mapfoldl(
                fun({W, ScaledW}, Extra) when W > 0, Extra > 0 ->
                        {ScaledW + 1, Extra - 1};
                   ({_, ScaledW}, Extra) ->
                        {ScaledW, Extra}
                end,
                Budget - lists:sum(Scaled),
                lists:zip(Weights, Scaled)),
            Widths
    end.

width_specs(Columns, Headers) ->
    width_specs(Columns, Headers, []).

width_specs([], _Headers, Acc) ->
    lists:reverse(Acc);
width_specs([Col | RestCols], [Header | RestHeaders], Acc) ->
    HeaderLen = string:length(to_string(Header)),
    width_specs(RestCols, RestHeaders, [{Col#table_col.width, HeaderLen} | Acc]);
width_specs([Col | RestCols], [], Acc) ->
    width_specs(RestCols, [], [{Col#table_col.width, 0} | Acc]).

initial_content_widths(WidthSpecs) ->
    [case Width of
         auto -> HeaderLen;
         {fixed, W} -> W;
         fill -> 0;
         W -> W
     end || {Width, HeaderLen} <- WidthSpecs].

update_content_widths(Widths, WidthSpecs, Row) ->
    lists:reverse(update_content_widths(Widths, WidthSpecs, Row, [])).

update_content_widths([], _Specs, _Row, Acc) ->
    Acc;
update_content_widths([Width | RestWidths], [{auto, _} | RestSpecs], [Cell | RestCells], Acc) ->
    CellWidth = string:length(to_string(Cell)),
    update_content_widths(RestWidths, RestSpecs, RestCells, [max(Width, CellWidth) | Acc]);
update_content_widths([Width | RestWidths], [{auto, _} | RestSpecs], [], Acc) ->
    update_content_widths(RestWidths, RestSpecs, [], [Width | Acc]);
update_content_widths([Width | RestWidths], [_Fixed | RestSpecs], [_Cell | RestCells], Acc) ->
    update_content_widths(RestWidths, RestSpecs, RestCells, [Width | Acc]);
update_content_widths([Width | RestWidths], [_Fixed | RestSpecs], [], Acc) ->
    update_content_widths(RestWidths, RestSpecs, [], [Width | Acc]).

toggle_sort(#table{sortable = false} = Table, _ColumnId) ->
    Table;
toggle_sort(#table{row_provider = Provider} = Table, _ColumnId) when Provider =/= undefined ->
    Table;
toggle_sort(#table{columns = Columns, rows = Rows, sort_by = CurrentSortBy,
                   sort_dir = CurrentSortDir} = Table, ColumnId) ->
    case column_index(Columns, ColumnId) of
        undefined ->
            Table;
        ColumnIdx ->
            SortDir = case CurrentSortBy of
                ColumnId when CurrentSortDir =:= asc -> desc;
                ColumnId -> asc;
                _ -> default_sort_dir(Rows, ColumnIdx)
            end,
            Sorted = apply_sort(Table#table{sort_by = ColumnId, sort_dir = SortDir},
                                selected_row_after_sort(Rows), 0),
            case Table#table.row_keys of
                [] -> Sorted;
                _ -> Sorted#table{selected_row = merged_selection(Table, Sorted)}
            end
    end.

%% A controlled view owns all state, including an intentional zero selection
%% or undefined sort. Never re-sort its rows or inherit state from the old view.
merge_sort_state(_Old, #table{controlled = true} = New) ->
    clamp_state(New);
merge_sort_state(#table{sort_by = OldSortBy, sort_dir = OldSortDir} = Old,
                 #table{sortable = true, row_provider = undefined} = New) ->
    SortBy = case New#table.sort_by of
        undefined -> OldSortBy;
        Value -> Value
    end,
    SortDir = case New#table.sort_by of
        undefined -> OldSortDir;
        _ -> New#table.sort_dir
    end,
    Sorted = case SortBy of
        undefined -> New;
        _ -> apply_sort(New#table{sort_by = SortBy, sort_dir = SortDir}, 0, 0)
    end,
    merge_selection(Old, Sorted);
merge_sort_state(#table{} = Old, #table{} = New) ->
    merge_selection(Old, New).

merge_selection(Old, New) ->
    clamp_state(New#table{selected_row = merged_selection(Old, New),
                          scroll_offset = Old#table.scroll_offset}).

merged_selection(#table{row_keys = [], selected_row = Selected}, _New) ->
    Selected;
merged_selection(#table{row_keys = OldKeys, selected_row = Selected},
                  #table{row_keys = NewKeys}) when Selected > 0, Selected =< length(OldKeys) ->
    key_index(lists:nth(Selected, OldKeys), NewKeys, 1);
merged_selection(_Old, _New) ->
    0.

key_index(_Key, [], _Index) -> 0;
key_index(Key, [Key | _], Index) -> Index;
key_index(Key, [_ | Rest], Index) -> key_index(Key, Rest, Index + 1).

clamp_state(#table{height = Height, selected_row = Selected} = Table) ->
    %% Without layout bounds, auto/fill can only be clamped to the last row.
    %% Rendering and hit testing additionally clamp to the resolved viewport.
    VisibleHeight = case Height of
        H when is_integer(H) -> max(1, H - overhead(Table));
        _ -> 1
    end,
    Table#table{selected_row = clamp_selected_row(Selected, total_rows(Table)),
                scroll_offset = clamp_scroll_offset(Table, VisibleHeight)}.

header_values(#table{columns = Columns, sortable = Sortable,
                     sort_by = SortBy, sort_dir = SortDir}) ->
    lists:map(
        fun(#table_col{id = ColumnId, header = Header}) ->
            case Sortable andalso ColumnId =:= SortBy of
                true ->
                    [Header, direction_suffix(SortDir)];
                false ->
                    Header
            end
        end,
        Columns).

apply_sort(#table{columns = Columns, rows = Rows, sort_by = SortBy,
                  sort_dir = SortDir, row_keys = Keys} = Table, SelectedRow, ScrollOffset) ->
    case column_index(Columns, SortBy) of
        undefined ->
            Table#table{selected_row = SelectedRow, scroll_offset = ScrollOffset};
        ColumnIdx ->
            Ordered = sort_rows(Rows, ColumnIdx, SortDir),
            SortedKeys = case Keys of
                [] -> [];
                _ ->
                    KeyTuple = list_to_tuple(Keys),
                    [element(Pos, KeyTuple) || {{_SortKey, Pos}, _Row} <- Ordered]
            end,
            Table#table{rows = [Row || {_Key, Row} <- Ordered], row_keys = SortedKeys,
                        selected_row = SelectedRow, scroll_offset = ScrollOffset}
    end.

sort_rows(Rows, ColumnIdx, SortDir) ->
    Decorated = [
        {{cell_sort_key(safe_nth(ColumnIdx, Row, <<>>)), Pos}, Row}
        || {Pos, Row} <- lists:zip(lists:seq(1, length(Rows)), Rows)
    ],
    Sorted = lists:keysort(1, Decorated),
    case SortDir of
        asc -> Sorted;
        desc -> lists:reverse(Sorted)
    end.

column_index(Columns, ColumnId) ->
    column_index(Columns, ColumnId, 1).

column_index([], _ColumnId, _Idx) ->
    undefined;
column_index([#table_col{id = ColumnId} | _], ColumnId, Idx) ->
    Idx;
column_index([_ | Rest], ColumnId, Idx) ->
    column_index(Rest, ColumnId, Idx + 1).

default_sort_dir(Rows, ColumnIdx) ->
    case sample_sort_kind(Rows, ColumnIdx) of
        number -> desc;
        text -> asc
    end.

sample_sort_kind([], _ColumnIdx) ->
    text;
sample_sort_kind([Row | Rest], ColumnIdx) ->
    case cell_sort_key(safe_nth(ColumnIdx, Row, <<>>)) of
        {number, _Value} -> number;
        {text, []} -> sample_sort_kind(Rest, ColumnIdx);
        {text, _Value} -> text
    end.

cell_sort_key(Value) when is_integer(Value) ->
    {number, Value};
cell_sort_key(Value) when is_float(Value) ->
    {number, Value};
cell_sort_key(Value) when is_binary(Value) ->
    sort_key_from_text(unicode:characters_to_list(Value));
cell_sort_key(Value) when is_list(Value) ->
    sort_key_from_text(Value);
cell_sort_key(Value) when is_atom(Value) ->
    {text, string:lowercase(atom_to_list(Value))};
cell_sort_key(Value) when is_pid(Value) ->
    {text, Value};
cell_sort_key(Value) ->
    {text, string:lowercase(lists:flatten(io_lib:format("~p", [Value])))}.

sort_key_from_text(Value) ->
    Text = string:trim(Value),
    case parse_bytes(Text) of
        {ok, Bytes} -> {number, Bytes};
        error ->
            case parse_number(Text) of
                {ok, Number} -> {number, Number};
                error -> {text, string:lowercase(Text)}
            end
    end.

parse_bytes(Text) ->
    case string:lexemes(Text, " ") of
        [Number, Unit] ->
            case parse_number(Number) of
                {ok, ParsedNumber} ->
                    case unit_multiplier(string:uppercase(Unit)) of
                        undefined -> error;
                        Multiplier -> {ok, ParsedNumber * Multiplier}
                    end;
                error ->
                    error
            end;
        _ ->
            error
    end.

parse_number([]) ->
    error;
parse_number(Text) ->
    Normalized = lists:filter(
        fun(Char) ->
            (Char >= $0 andalso Char =< $9) orelse Char =:= $. orelse Char =:= $- orelse Char =:= $+
        end,
        Text
    ),
    case Normalized of
        [] ->
            error;
        _ ->
            case string:find(Normalized, ".") of
                nomatch ->
                    case string:to_integer(Normalized) of
                        {Int, []} -> {ok, Int};
                        _ -> error
                    end;
                _ ->
                    case string:to_float(Normalized) of
                        {Float, []} -> {ok, Float};
                        _ -> error
                    end
            end
    end.

unit_multiplier("B") -> 1;
unit_multiplier("KB") -> 1024;
unit_multiplier("MB") -> 1024 * 1024;
unit_multiplier("GB") -> 1024 * 1024 * 1024;
unit_multiplier("TB") -> 1024 * 1024 * 1024 * 1024;
unit_multiplier(_) -> undefined.

direction_suffix(asc) -> " ^";
direction_suffix(desc) -> " v".

selected_row_after_sort([]) -> 0;
selected_row_after_sort(_) -> 1.

clamp_selected_row(_SelectedRow, 0) ->
    0;
clamp_selected_row(SelectedRow, TotalRows) ->
    min(max(SelectedRow, 0), TotalRows).

render_table_row_text(RowData, ColWidths, Columns, ColumnSeparator) ->
    Cells = render_table_cells(RowData, ColWidths, Columns, []),
    unicode:characters_to_binary(lists:join(ColumnSeparator, Cells)).

render_table_cells(_RowData, [], _Columns, Acc) ->
    lists:reverse(Acc);
render_table_cells([Data | RestData], [Width | RestWidths], [Col | RestCols], Acc) ->
    Cell = format_cell(to_string(Data), Width, Col#table_col.align),
    render_table_cells(RestData, RestWidths, RestCols, [Cell | Acc]);
render_table_cells([], [Width | RestWidths], [Col | RestCols], Acc) ->
    Cell = format_cell(to_string(<<>>), Width, Col#table_col.align),
    render_table_cells([], RestWidths, RestCols, [Cell | Acc]);
render_table_cells([Data | RestData], [Width | RestWidths], [], Acc) ->
    Cell = format_cell(to_string(Data), Width, left),
    render_table_cells(RestData, RestWidths, [], [Cell | Acc]);
render_table_cells([], [Width | RestWidths], [], Acc) ->
    Cell = format_cell(to_string(<<>>), Width, left),
    render_table_cells([], RestWidths, [], [Cell | Acc]).

format_cell(_Text, Width, _Align) when Width =< 0 ->
    [];
format_cell(Text, Width, Align) ->
    Len = string:length(Text),
    if
        Len >= Width -> string:slice(Text, 0, Width);
        true ->
            Padding = Width - Len,
            case Align of
                left -> [Text, lists:duplicate(Padding, $\s)];
                right -> [lists:duplicate(Padding, $\s), Text];
                center ->
                    Left = Padding div 2,
                    Right = Padding - Left,
                    [lists:duplicate(Left, $\s), Text, lists:duplicate(Right, $\s)]
            end
    end.

to_string(Bin) when is_binary(Bin) -> unicode:characters_to_list(Bin);
to_string(List) when is_list(List) -> List;
to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_string(Int) when is_integer(Int) -> integer_to_list(Int);
to_string(Float) when is_float(Float) -> float_to_list(Float, [{decimals, 2}]);
to_string(Pid) when is_pid(Pid) -> pid_to_list(Pid);
to_string(Other) -> io_lib:format("~p", [Other]).

safe_nth(1, [Value | _], _Default) ->
    Value;
safe_nth(N, [_ | Rest], Default) when N > 1 ->
    safe_nth(N - 1, Rest, Default);
safe_nth(_, _, Default) ->
    Default.

header_height(#table{show_header = false}) -> 0;
header_height(#table{header_separator = false}) -> 1;
header_height(#table{}) -> 2.

overhead(#table{border = Border} = Table) ->
    BorderOffset = case Border of none -> 0; _ -> 1 end,
    2 * BorderOffset + header_height(Table).

column_separator_width(#table{column_separator = Separator}) ->
    string:length(Separator).

total_rows(#table{total_rows = undefined, rows = Rows}) -> length(Rows);
total_rows(#table{total_rows = Total}) -> Total.

clamp_scroll_offset(#table{scroll_offset = Offset} = Table, VisibleHeight) ->
    min(max(0, Offset), max(0, total_rows(Table) - max(1, VisibleHeight))).

visible_rows(Table, VisibleHeight) ->
    Offset = clamp_scroll_offset(Table, VisibleHeight),
    Count = min(max(0, VisibleHeight), max(0, total_rows(Table) - Offset)),
    case {Count, Table#table.row_provider} of
        {0, _} -> [];
        {_, undefined} ->
            Rows = Table#table.rows,
            lists:sublist(lists:nthtail(min(Offset, length(Rows)), Rows), Count);
        {_, Provider} when is_function(Provider, 2) ->
            lists:sublist(Provider(Offset, Count), Count)
    end.

pad_line(Text, Width) when Width =< 0 ->
    case Text of
        Bin when is_binary(Bin) -> <<>>;
        _ -> []
    end;
pad_line(Text, Width) ->
    Line = iolist_to_binary(Text),
    Len = string:length(unicode:characters_to_list(Line)),
    case Len >= Width of
        true ->
            unicode:characters_to_binary(string:slice(Line, 0, Width));
        false ->
            [Line, lists:duplicate(Width - Len, $\s)]
    end.

blank_line(Width) when Width =< 0 ->
    [];
blank_line(Width) ->
    lists:duplicate(Width, $\s).

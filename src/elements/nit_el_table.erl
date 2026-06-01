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

%%====================================================================
%% nit_element callbacks
%%====================================================================

-spec render(#table{}, #bounds{}, map()) -> iolist().
render(#table{visible = false}, _Bounds, _Opts) ->
    [];
render(#table{} = Table0, Bounds, Opts) ->
    #table{columns = Columns, rows = StaticRows, selected_row = SelectedRow,
              scroll_offset = ScrollOffset, border = Border, show_header = ShowHeader,
              zebra = Zebra, style = Style, x = X, y = Y, width = W, height = H,
              total_rows = TotalRows, row_provider = RowProvider} = Table0,
    ActualX = Bounds#bounds.x + X,
    ActualY = Bounds#bounds.y + Y,
    Focused = maps:get(focused, Opts, false),
    BaseStyle = maps:get(base_style, Opts, #{}),
    MergedStyle = maps:merge(Style, BaseStyle),

    Width = case W of
        auto -> Bounds#bounds.width - X;
        fill -> Bounds#bounds.width - X;
        _ -> W
    end,

    %% Determine total row count (virtual scrolling or static)
    ActualTotalRows = case TotalRows of
        undefined -> length(StaticRows);
        N -> N
    end,

    Overhead = table_overhead(Border, ShowHeader),
    Height = case H of
        auto -> min(ActualTotalRows + Overhead, Bounds#bounds.height - Y);
        fill -> max(Overhead + 1, Bounds#bounds.height - Y);
        _ -> H
    end,

    BorderOffset = case Border of none -> 0; _ -> 1 end,
    HeaderOffset2 = case ShowHeader of true -> 2; false -> 0 end,
    VisibleHeight = max(0, Height - 2 * BorderOffset - HeaderOffset2),

    %% Fetch visible rows (virtual scrolling or static)
    VisibleRows = case RowProvider of
        undefined ->
            %% Static mode - use rows field
            lists:sublist(
                lists:nthtail(min(ScrollOffset, max(0, length(StaticRows) - 1)), StaticRows),
                max(0, VisibleHeight));
        Provider when is_function(Provider, 2) ->
            %% Virtual scrolling mode - fetch from provider
            Provider(ScrollOffset, VisibleHeight)
    end,

    %% For column width calculation, use visible rows (or sample for virtual)
    ColWidths = calculate_column_widths(header_values(Table0), Columns, VisibleRows,
                                        Width - 2 * BorderOffset),

    ContentWidth = max(0, Width - 2 * BorderOffset),
    HeaderRow = render_header(ShowHeader, header_values(Table0), Columns, ColWidths, MergedStyle,
                              ActualX, ActualY, BorderOffset, Width, ContentWidth),

    DataRows = render_visible_rows(VisibleRows, Columns, ColWidths, SelectedRow, ScrollOffset,
                                   Zebra, Focused, MergedStyle, ActualX, ActualY,
                                   BorderOffset, HeaderOffset2, ContentWidth),

    EmptyRows = render_empty_rows(length(VisibleRows), VisibleHeight, MergedStyle,
                                  ActualX, ActualY, BorderOffset, HeaderOffset2, ContentWidth),

    BorderOutput = render_border(Border, MergedStyle, ActualX, ActualY, Width, Height),

    [BorderOutput, HeaderRow, DataRows, EmptyRows].

-spec height(#table{}, #bounds{}) -> pos_integer() | {flex, non_neg_integer()}.
height(#table{height = H, rows = Rows, total_rows = TotalRows,
              border = Border, show_header = ShowHeader}, Bounds) ->
    ActualTotalRows = case TotalRows of
        undefined -> length(Rows);
        N -> N
    end,
    case H of
        auto -> min(ActualTotalRows + table_overhead(Border, ShowHeader), Bounds#bounds.height);
        fill -> {flex, table_overhead(Border, ShowHeader) + 1};
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

render_header(false, _Headers, _Columns, _ColWidths, _Style, _X, _Y, _BO, _W, _ContentW) -> [];
render_header(true, Headers, Columns, ColWidths, Style, ActualX, ActualY, BorderOffset, Width, ContentWidth) ->
    HeaderText = pad_line(render_table_row_text(
        Headers, ColWidths, Columns), ContentWidth),
    HeaderY = ActualY + BorderOffset + 1,
    SepY = ActualY + BorderOffset + 2,
    [
        nit_ansi:move_to(HeaderY, ActualX + BorderOffset + 1),
        nit_ansi:style_to_ansi(maps:merge(Style, #{bold => true})),
        HeaderText,
        nit_ansi:reset_style(),
        nit_ansi:move_to(SepY, ActualX + BorderOffset + 1),
        nit_ansi:style_to_ansi(Style),
        nit_ansi:repeat_bin(<<"─"/utf8>>, Width - 2 * BorderOffset),
        nit_ansi:reset_style()
    ].

%% Render already-fetched visible rows (works for both static and virtual scrolling)
render_visible_rows(VisibleRows, Columns, ColWidths, SelectedRow, ScrollOffset,
                    Zebra, Focused, Style, ActualX, ActualY, BorderOffset, HeaderOffset2,
                    ContentWidth) ->
    lists:map(
        fun({RowIdx, RowData}) ->
            AbsRowIdx = ScrollOffset + RowIdx,
            IsSelected = AbsRowIdx =:= SelectedRow,
            RowStyle = if
                IsSelected andalso Focused ->
                    maps:merge(Style, #{bg => white, fg => black, bold => true});
                IsSelected ->
                    maps:merge(Style, #{bg => cyan, fg => black});
                Zebra andalso (AbsRowIdx rem 2 =:= 1) ->
                    maps:merge(Style, #{dim => true});
                true -> Style
            end,
            RowText = pad_line(render_table_row_text(RowData, ColWidths, Columns), ContentWidth),
            RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx,
            [
                nit_ansi:move_to(RowY, ActualX + BorderOffset + 1),
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
            RowY = ActualY + BorderOffset + HeaderOffset2 + RowIdx,
            [
                nit_ansi:move_to(RowY, ActualX + BorderOffset + 1),
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
        nit_ansi:move_to(ActualY + 1, ActualX + 1),
        TL, nit_ansi:repeat_bin(HZ, Width - 2), TR,
        [[nit_ansi:move_to(ActualY + 1 + Row, ActualX + 1),
          VT, lists:duplicate(Width - 2, $\s), VT]
         || Row <- lists:seq(1, Height - 2)],
        nit_ansi:move_to(ActualY + Height, ActualX + 1),
        BL, nit_ansi:repeat_bin(HZ, Width - 2), BR,
        nit_ansi:reset_style()
    ].

calculate_column_widths(Headers, Columns, Rows, AvailableWidth) ->
    WidthSpecs = width_specs(Columns, Headers),
    ContentWidths0 = initial_content_widths(WidthSpecs),
    ContentWidths = lists:foldl(
        fun(Row, Widths) ->
            update_content_widths(Widths, WidthSpecs, Row)
        end,
        ContentWidths0,
        Rows),
    NumCols = length(ContentWidths),
    TotalWidth = lists:sum(ContentWidths) + NumCols - 1,
    if
        TotalWidth =< AvailableWidth -> ContentWidths;
        true ->
            Scale = AvailableWidth / max(1, TotalWidth),
            [max(3, round(W * Scale)) || W <- ContentWidths]
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
            apply_sort(Table#table{sort_by = ColumnId, sort_dir = SortDir},
                       selected_row_after_sort(Rows), 0)
    end.

merge_sort_state(#table{selected_row = OldSel, scroll_offset = OldOff,
                        sort_by = OldSortBy, sort_dir = OldSortDir},
                 #table{sortable = true, row_provider = undefined} = New) ->
    SortBy = case New#table.sort_by of
        undefined -> OldSortBy;
        Value -> Value
    end,
    SortDir = case New#table.sort_by of
        undefined -> OldSortDir;
        _ -> New#table.sort_dir
    end,
    Merged = case SortBy of
        undefined -> New#table{selected_row = OldSel, scroll_offset = OldOff};
        _ -> apply_sort(New#table{sort_by = SortBy, sort_dir = SortDir}, OldSel, OldOff)
    end,
    Merged#table{
        selected_row = clamp_selected_row(Merged#table.selected_row, length(Merged#table.rows)),
        scroll_offset = max(0, Merged#table.scroll_offset)
    };
merge_sort_state(#table{selected_row = OldSel, scroll_offset = OldOff},
                 #table{} = New) ->
    New#table{selected_row = OldSel, scroll_offset = OldOff}.

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
                  sort_dir = SortDir} = Table, SelectedRow, ScrollOffset) ->
    case column_index(Columns, SortBy) of
        undefined ->
            Table#table{selected_row = SelectedRow, scroll_offset = ScrollOffset};
        ColumnIdx ->
            SortedRows = sort_rows(Rows, ColumnIdx, SortDir),
            Table#table{rows = SortedRows, selected_row = SelectedRow, scroll_offset = ScrollOffset}
    end.

sort_rows(Rows, ColumnIdx, SortDir) ->
    Decorated = [
        {{cell_sort_key(safe_nth(ColumnIdx, Row, <<>>)), Pos}, Row}
        || {Pos, Row} <- lists:zip(lists:seq(1, length(Rows)), Rows)
    ],
    Sorted = lists:keysort(1, Decorated),
    Ordered = case SortDir of
        asc -> Sorted;
        desc -> lists:reverse(Sorted)
    end,
    [Row || {_Key, Row} <- Ordered].

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
    min(max(SelectedRow, 1), TotalRows).

render_table_row_text(RowData, ColWidths, Columns) ->
    Cells = render_table_cells(RowData, ColWidths, Columns, []),
    lists:join(<<" ">>, Cells).

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

table_overhead(Border, ShowHeader) ->
    BorderOffset = case Border of none -> 0; _ -> 1 end,
    HeaderOffset = case ShowHeader of true -> 2; false -> 0 end,
    2 * BorderOffset + HeaderOffset.

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
            Line;
        false ->
            [Line, lists:duplicate(Width - Len, $\s)]
    end.

blank_line(Width) when Width =< 0 ->
    [];
blank_line(Width) ->
    lists:duplicate(Width, $\s).

-module(nit_table_unicode_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

auto_headers_data_and_sort_suffix_use_cells_test() ->
    Table = (table([auto, auto], [<<"界"/utf8>>, <<"N">>],
                   [<<"x">>, [16#6F22, 16#5B57]]))#table{sortable = true, sort_by = 1},
    assert_geometry(Table, 9, [4, 4], 1,
                    <<"界 ^|N   "/utf8>>, <<"x   |漢字"/utf8>>).

constrained_auto_header_reserves_terminal_cells_test() ->
    Table = table([{fixed, 2}, auto, fill], [<<"F">>, <<"界界"/utf8>>, <<"P">>],
                  [<<"z">>, <<"x">>, <<"漢字語"/utf8>>]),
    assert_geometry(Table, 11, [2, 4, 3], 1,
                    <<"F |界界|P  "/utf8>>, <<"z |x   |漢 "/utf8>>).

fixed_fill_cjk_overflow_all_alignments_test_() ->
    [?_test(begin
        Text = <<"界語文"/utf8>>,
        Table = align(table([{fixed, Width}, fill], [Text, Text], [Text, Text]), Align),
        Cell = case {Width, Align} of
            {1, _} -> <<" ">>;
            {2, _} -> <<"界"/utf8>>;
            {3, right} -> <<" 界"/utf8>>;
            {3, _} -> <<"界 "/utf8>>;
            {5, right} -> <<" 界語"/utf8>>;
            {5, _} -> <<"界語 "/utf8>>
        end,
        Expected = iolist_to_binary([Cell, <<"|">>, Cell]),
        assert_geometry(Table, Width * 2 + 1, [Width, Width], 1, Expected, Expected)
    end) || Width <- [1, 2, 3, 5], Align <- [left, center, right]].

cjk_padding_all_alignments_test_() ->
    [?_test(begin
        Text = <<"界"/utf8>>,
        Table = align(table([{fixed, 5}, fill], [Text, Text], [Text, Text]), Align),
        Expected = iolist_to_binary([Cell, <<"|">>, Cell]),
        assert_geometry(Table, 11, [5, 5], 1, Expected, Expected)
    end) || {Align, Cell} <- [{left, <<"界   "/utf8>>}, {center, <<" 界  "/utf8>>},
                              {right, <<"   界"/utf8>>}]].

custom_separator_render_and_hit_agreement_test_() ->
    [?_test(begin
        Cells = [<<"漢字"/utf8>>, <<"語字文"/utf8>>],
        Table = (table([{fixed, 3}, fill], Cells, Cells))#table{
            border = Border, column_separator = Separator},
        Expected = unicode:characters_to_binary([<<"漢 "/utf8>>, Separator, <<"語字"/utf8>>]),
        assert_geometry(Table, 7 + SepWidth, [3, 4], SepWidth, Expected, Expected)
    end) || Border <- [none, single],
            {Separator, SepWidth} <- [{<<"界"/utf8>>, 2}, {[16#754C], 2},
                                     {<<" 界 "/utf8>>, 4}, {<<"界"/utf8, 16#301/utf8>>, 2},
                                     {<<"e", 16#301/utf8>>, 1}, {<<>>, 0}]].

table_edge_clips_wide_cells_and_separators_test_() ->
    [?_test(begin
        Cells = [<<"界界界界"/utf8>>, <<"語字"/utf8>>],
        Table = (table([{fixed, 7}, fill], Cells, Cells))#table{
            border = Border, column_separator = <<"界"/utf8>>},
        assert_geometry(Table, Width, [7, max(0, Width - 9)], 2, Expected, Expected)
    end) || Border <- [none, single], {Width, Expected} <- [
        {0, <<>>}, {1, <<" ">>}, {2, <<"界"/utf8>>}, {3, <<"界 "/utf8>>},
        {4, <<"界界"/utf8>>}, {5, <<"界界 "/utf8>>}, {6, <<"界界界"/utf8>>},
        {7, <<"界界界 "/utf8>>}, {8, <<"界界界  "/utf8>>},
        {9, <<"界界界 界"/utf8>>}, {10, <<"界界界 界 "/utf8>>}
    ]].

combining_marks_survive_cell_clipping_test_() ->
    [?_test(begin
        Text = <<"e", 16#301/utf8, "界"/utf8>>,
        Table = align(table([{fixed, 1}, fill], [Text, Text], [Text, Text]), Align),
        Cell = case Align of
            right -> <<" e", 16#301/utf8>>;
            _ -> <<"e", 16#301/utf8, " ">>
        end,
        Expected = iolist_to_binary([<<"e", 16#301/utf8, "|">>, Cell]),
        assert_geometry(Table, 4, [1, 2], 1, Expected, Expected)
    end) || Align <- [left, center, right]].

combining_auto_width_and_trailing_padding_test() ->
    Cells = [[101, 16#301], <<"界"/utf8, 16#301/utf8>>],
    Table = table([auto, auto], Cells, Cells),
    Expected = <<"e", 16#301/utf8, "|界"/utf8, 16#301/utf8, "   ">>,
    assert_geometry(Table, 7, [1, 2], 1, Expected, Expected).

combining_marks_survive_table_edge_clipping_test() ->
    Text = <<"e", 16#301/utf8, "界"/utf8>>,
    Table = table([{fixed, 3}, fill], [Text, Text], [Text, Text]),
    Expected = <<"e", 16#301/utf8>>,
    assert_geometry(Table, 1, [3, 0], 1, Expected, Expected).

ascii_legacy_scaling_and_clipping_test_() ->
    [?_test(begin
        Cells = [<<"abcd">>, <<"defg">>],
        Table = table(Specs, Cells, Cells),
        assert_geometry(Table, 6, [3, 3], 1, <<"abc|de">>, <<"abc|de">>)
    end) || Specs <- [[4, 4], [auto, auto], [auto, 4]]].

table(Specs, Headers, Cells) ->
    Ids = lists:seq(1, length(Specs)),
    Columns = [#table_col{id = Id, header = Header, width = Spec}
               || {Id, {Spec, Header}} <- lists:zip(Ids, lists:zip(Specs, Headers))],
    #table{id = unicode_table, columns = Columns, rows = [Cells], zebra = false,
           header_separator = false, column_separator = "|", clickable_columns = Ids}.

align(Table, Align) ->
    Table#table{columns = [Col#table_col{align = Align} || Col <- Table#table.columns]}.

%% Inspect actual ANSI row output rather than nit_screen, whose parser advances
%% one position per codepoint. Check every terminal cell, including wide glyph
%% continuations and padding, against the public one-based mouse hit API.
assert_geometry(Table0, ContentWidth, Widths, SepWidth, ExpectedHeader, ExpectedRow) ->
    BO = case Table0#table.border of none -> 0; _ -> 1 end,
    Width = ContentWidth + 2 * BO,
    Table = Table0#table{x = 2, y = 1, width = Width, height = 2 + 2 * BO},
    Bounds = #bounds{x = 3, y = 2, width = Width + 2, height = 8},
    X = Bounds#bounds.x + Table#table.x + BO,
    Y = Bounds#bounds.y + Table#table.y + BO,
    ?assertEqual(Widths, nit_el_table:column_widths(Table, Table#table.rows, ContentWidth)),
    ?assertEqual(SepWidth, nit_el_table:column_separator_width(Table)),
    Rendered = iolist_to_binary(nit_el_table:render(Table, Bounds, #{})),
    lists:foreach(fun({Row, Expected}) ->
        Actual = rendered_row(Rendered, X, Row),
        ?assertEqual(Expected, Actual),
        ?assertEqual(ContentWidth, nit_unicode:display_width(Actual))
    end, [{Y, ExpectedHeader}, {Y + 1, ExpectedRow}]),
    Trailing = lists:duplicate(ContentWidth, undefined),
    HeaderIds = hit_ids(Widths, SepWidth, true) ++ Trailing,
    CellIds = hit_ids(Widths, SepWidth, false) ++ Trailing,
    lists:foreach(fun(Offset) ->
        HeaderHit = case lists:nth(Offset, HeaderIds) of
            undefined -> {table, unicode_table};
            HeaderId -> {table_header, unicode_table, HeaderId}
        end,
        CellHit = case lists:nth(Offset, CellIds) of
            undefined -> {table_row, unicode_table, 1};
            CellId -> {table_cell, unicode_table, 1, CellId}
        end,
        ?assertEqual(HeaderHit, nit_hit:find_at(Table, X + Offset, Y + 1, Bounds)),
        ?assertEqual(CellHit, nit_hit:find_at(Table, X + Offset, Y + 2, Bounds))
    end, lists:seq(1, ContentWidth)),
    OutsideX = Bounds#bounds.x + Table#table.x + Width + 1,
    ?assertEqual(not_found, nit_hit:find_at(Table, OutsideX, Y + 1, Bounds)),
    ?assertEqual(not_found, nit_hit:find_at(Table, OutsideX, Y + 2, Bounds)).

%% Headers retain their following separator; data separators select the row.
hit_ids(Widths, SepWidth, Header) ->
    lists:append([lists:duplicate(W, Id) ++
                  lists:duplicate(case Id < length(Widths) of true -> SepWidth; false -> 0 end,
                                  case Header of true -> Id; false -> undefined end)
                  || {Id, W} <- lists:zip(lists:seq(1, length(Widths)), Widths)]).

rendered_row(Rendered, X, Y) ->
    Clean = re:replace(Rendered, <<"\e\\[[0-9;]*m|\e\\([AB]">>, <<>>,
                       [global, {return, binary}]),
    [_Before, RowAndRest] = binary:split(Clean, nit_ansi:move_to(Y, X)),
    hd(binary:split(RowAndRest, <<"\e">>)).
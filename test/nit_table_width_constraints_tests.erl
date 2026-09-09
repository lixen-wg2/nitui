-module(nit_table_width_constraints_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

fixed_fill_preview_test_() ->
    [?_test(begin
        Table = table([{fixed, 7}, fill], [<<"123456789">>, binary:copy(<<"p">>, 4096)]),
        ?assertEqual([7, Width - 8], widths(Table, Width)),
        ?assertEqual([7, Width - 8], nit_el_table:column_widths(Table, [], Width))
    end) || Width <- [60, 80, 160]].

mixed_specs_test_() ->
    [?_test(begin
        Table = table([{fixed, 7}, auto, 4, fill],
                      [<<"fixed header too long">>, <<"abcdefgh">>, <<"integer ignores content">>,
                       binary:copy(<<"p">>, 4096)]),
        ?assertEqual(Expected, widths(Table, Width))
    end) || {Width, Expected} <- [{30, [7, 8, 4, 8]}, {22, [7, 8, 4, 0]},
                                  {21, [7, 8, 3, 0]}, {15, [7, 4, 1, 0]},
                                  {12, [7, 2, 0, 0]}, {10, [7, 0, 0, 0]}]].

fixed_without_fill_preserves_preferences_test() ->
    Table = table([{fixed, 7}, auto, 4], [<<"long fixed header">>, <<"abcdefgh">>, <<"int">>]),
    ?assertEqual([7, 8, 4], widths(Table, 60)),
    ?assertEqual([7, 4, 2], widths(Table, 15)).

multiple_fills_share_remainder_left_to_right_test_() ->
    [?_test(begin
        Table = table([fill, {fixed, 7}, fill, fill],
                      [<<"a">>, <<"fixed">>, binary:copy(<<"b">>, 4096), <<"c">>]),
        ?assertEqual(Expected, widths(Table, Width))
    end) || {Width, Expected} <- [{9, [0, 7, 0, 0]}, {10, [0, 7, 0, 0]},
                                  {11, [1, 7, 0, 0]}, {12, [1, 7, 1, 0]},
                                  {13, [1, 7, 1, 1]}, {18, [3, 7, 3, 2]}]].

fill_only_and_empty_preferences_test() ->
    ?assertEqual([9], widths(table([fill], [<<>>]), 9)),
    ?assertEqual([3, 2, 2], widths(table([fill, fill, fill], [<<>>, <<>>, <<>>]), 9)),
    Table = table([auto, 3, fill, {fixed, 1}], [<<>>, <<"integer">>, <<"fill">>, <<"x">>]),
    ?assertEqual([0, 2, 0, 1], widths(Table, 6)),
    ?assertEqual([0, 3, 3, 1], widths(Table, 10)).

tiny_and_negative_budgets_test_() ->
    [?_test(begin
        Table = table([{fixed, 7}, auto, 4, fill],
                      [<<"fixed">>, <<"abcdefghij">>, <<"int">>, <<"fill">>]),
        [Fixed | Flexible] = widths(Table, Width),
        ?assertEqual(7, Fixed),
        ?assert(lists:all(fun(W) -> is_integer(W) andalso W >= 0 end, Flexible)),
        ?assertEqual(max(0, Width - 10), lists:sum(Flexible)),
        ?assertEqual([7, 5], widths(table([{fixed, 7}, {fixed, 5}], [<<"x">>, <<"y">>]), Width))
    end) || Width <- lists:seq(-5, 12)].

constrained_budget_invariants_test_() ->
    [?_test(begin
        Table = table([auto, fill, {fixed, 7}, 4, fill],
                      [<<"abcdefgh">>, <<"b">>, <<"c">>, <<"d">>, <<"e">>]),
        [Auto, Fill1, Fixed, Int, Fill2] = widths(Table, Width),
        ?assertEqual(7, Fixed),
        ?assert(Auto >= 0 andalso Auto =< 8),
        ?assert(Int >= 0 andalso Int =< 4),
        ?assert(Fill1 >= Fill2 andalso Fill1 - Fill2 =< 1),
        ?assertEqual(max(0, Width - 11), Auto + Fill1 + Int + Fill2),
        case Width >= 23 of
            true -> ?assertEqual({8, 4}, {Auto, Int});
            false -> ?assertEqual({0, 0}, {Fill1, Fill2})
        end
    end) || Width <- lists:seq(0, 80)].

auto_uses_sort_header_and_supplied_rows_test() ->
    Table = (table([{fixed, 7}, auto, fill], [<<"fixed">>, <<"N">>, <<"preview">>]))#table{
        sortable = true, sort_by = 2, rows = [[<<"x">>, <<"long row">>, <<>>]]},
    ?assertEqual([7, 3, 8], nit_el_table:column_widths(Table, [[<<"x">>, <<"n">>]], 20)),
    ?assertEqual([7, 8, 3], widths(Table, 20)),
    %% Missing cells retain header preferences; extra cells are ignored.
    ?assertEqual([7, 3, 8], nit_el_table:column_widths(Table, [[], [<<"x">>]], 20)),
    ?assertEqual([7, 3, 8], nit_el_table:column_widths(Table, [[<<>>, <<>>, <<>>, <<"extra">>]], 20)).

unicode_separator_budget_test_() ->
    [?_test(begin
        Table = (table([{fixed, 7}, fill], [<<"fixed">>, <<"preview">>]))#table{
            column_separator = Separator},
        ?assertEqual(SepWidth, nit_el_table:column_separator_width(Table)),
        ?assertEqual([7, 60 - 7 - SepWidth], widths(Table, 60)),
        ?assertEqual([7, 0], widths(Table, SepWidth - 1))
    end) || {Separator, SepWidth} <- [{<<"│"/utf8>>, 1}, {[16#2502], 1},
                                     {<<" │ "/utf8>>, 3}, {" | ", 3}, {<<>>, 0}]].

no_columns_test() ->
    Table = table([], []),
    lists:foreach(fun(Width) -> ?assertEqual([], widths(Table, Width)) end, [-1, 0, 20]),
    assert_geometry(Table, 0, <<>>, [], []),
    assert_geometry(Table, 5, <<"     ">>, lists:duplicate(5, undefined),
                    lists:duplicate(5, undefined)).

legacy_scaling_unchanged_test_() ->
    [?_test(begin
        Table = (table(Specs, [<<"abcdefgh">>, <<"ijkl">>]))#table{column_separator = " | "},
        Total = lists:sum(Preferred) + 3,
        Expected = case Total =< Width of
            true -> Preferred;
            false -> [max(3, round(W * (Width / max(1, Total)))) || W <- Preferred]
        end,
        ?assertEqual(Expected, widths(Table, Width))
    end) || {Specs, Preferred} <- [{[auto, auto], [8, 4]}, {[8, 7], [8, 7]},
                                   {[auto, 7], [8, 7]}],
            Width <- [-1, 0, 4, 8, 20, 60]].

preview_render_and_hit_agreement_test_() ->
    [?_test(begin
        Table = (table([{fixed, 7}, fill], [<<"123456789">>, binary:copy(<<"p">>, 4096)]))#table{
            border = Border, column_separator = Separator},
        PreviewWidth = Width - 7 - SepWidth,
        ?assertEqual([7, PreviewWidth], widths(Table, Width)),
        Expected = unicode:characters_to_binary([<<"1234567">>, Separator,
                                                 binary:copy(<<"p">>, PreviewWidth)]),
        HeaderIds = lists:duplicate(7 + SepWidth, 1) ++ lists:duplicate(PreviewWidth, 2),
        CellIds = lists:duplicate(7, 1) ++ lists:duplicate(SepWidth, undefined) ++
                  lists:duplicate(PreviewWidth, 2),
        assert_geometry(Table, Width, Expected, HeaderIds, CellIds)
    end) || Width <- [60, 80, 160], Border <- [none, single],
            {Separator, SepWidth} <- [{<<"│"/utf8>>, 1}, {<<" │ "/utf8>>, 3}, {<<>>, 0}]].

tiny_render_clips_fixed_and_zero_width_columns_test_() ->
    [?_test(begin
        Table = (table([{fixed, 7}, fill], [<<"123456789">>, binary:copy(<<"p">>, 4096)]))#table{
            border = Border, column_separator = <<"│"/utf8>>},
        ?assertEqual([7, max(0, Width - 8)], widths(Table, Width)),
        Expected = unicode:characters_to_binary(string:slice(<<"1234567│p"/utf8>>, 0, Width)),
        HeaderIds = lists:sublist(lists:duplicate(8, 1) ++ [2], Width),
        CellIds = lists:sublist(lists:duplicate(7, 1) ++ [undefined, 2], Width),
        assert_geometry(Table, Width, Expected, HeaderIds, CellIds)
    end) || Width <- lists:seq(0, 9), Border <- [none, single]].

mixed_render_and_hit_agreement_test_() ->
    [?_test(begin
        Table = (table([{fixed, 4}, auto, 4, fill],
                       [<<"fffff">>, <<"aaaaaaaa">>, <<"iiii">>, binary:copy(<<"p">>, 4096)]))#table{
            column_separator = <<"│"/utf8>>},
        ?assertEqual(ExpectedWidths, widths(Table, Width)),
        assert_geometry(Table, Width, Expected, HeaderIds, CellIds)
    end) || {Width, ExpectedWidths, Expected, HeaderIds, CellIds} <- [
        {12, [4, 4, 1, 0], <<"ffff│aaaa│i│"/utf8>>,
         lists:duplicate(5, 1) ++ lists:duplicate(5, 2) ++ [3, 3],
         lists:duplicate(4, 1) ++ [undefined] ++ lists:duplicate(4, 2) ++ [undefined, 3, undefined]},
        {24, [4, 8, 4, 5], <<"ffff│aaaaaaaa│iiii│ppppp"/utf8>>,
         lists:duplicate(5, 1) ++ lists:duplicate(9, 2) ++ lists:duplicate(5, 3) ++ lists:duplicate(5, 4),
         lists:duplicate(4, 1) ++ [undefined] ++ lists:duplicate(8, 2) ++ [undefined] ++
         lists:duplicate(4, 3) ++ [undefined] ++ lists:duplicate(5, 4)}
    ]].

fill_padding_is_rendered_and_clickable_test_() ->
    [?_test(begin
        Table0 = table([{fixed, 7}, fill], [<<"1234567">>, <<"p">>]),
        Table = Table0#table{column_separator = <<"│"/utf8>>,
                             columns = [Col#table_col{align = Align} || Col <- Table0#table.columns]},
        Expected = unicode:characters_to_binary([<<"1234567│"/utf8>>, Padding]),
        assert_geometry(Table, 12, Expected, lists:duplicate(8, 1) ++ lists:duplicate(4, 2),
                        lists:duplicate(7, 1) ++ [undefined] ++ lists:duplicate(4, 2))
    end) || {Align, Padding} <- [{left, <<"p   ">>}, {center, <<" p  ">>}, {right, <<"   p">>}]].

zero_width_columns_keep_separators_and_hit_positions_test_() ->
    [?_test(begin
        Table0 = table(Specs, Cells),
        Table = Table0#table{column_separator = <<"│"/utf8>>,
                             columns = [Col#table_col{align = Align} || Col <- Table0#table.columns]},
        ?assertEqual(ExpectedWidths, widths(Table, Width)),
        assert_geometry(Table, Width, Expected, HeaderIds, CellIds)
    end) || Align <- [left, center, right],
            {Specs, Cells, Width, ExpectedWidths, Expected, HeaderIds, CellIds} <- [
                {[fill, {fixed, 7}, auto], [<<"fill">>, <<"1234567">>, <<"auto">>], 7,
                 [0, 7, 0], <<"│123456"/utf8>>, [1, 2, 2, 2, 2, 2, 2],
                 [undefined, 2, 2, 2, 2, 2, 2]},
                {[{fixed, 3}, auto, fill, {fixed, 2}], [<<"aaa">>, <<"bbbb">>, <<"c">>, <<"dd">>], 8,
                 [3, 0, 0, 2], <<"aaa│││dd"/utf8>>, [1, 1, 1, 1, 2, 3, 4, 4],
                 [1, 1, 1, undefined, undefined, undefined, 4, 4]},
                {[fill, fill, fill], [<<"aaa">>, <<"bbb">>, <<"ccc">>], 4,
                 [1, 1, 0], <<"a│b│"/utf8>>, [1, 1, 2, 2], [1, undefined, 2, undefined]},
                {[fill, fill, fill], [<<"aaa">>, <<"bbb">>, <<"ccc">>], 10,
                 [3, 3, 2], <<"aaa│bbb│cc"/utf8>>, [1, 1, 1, 1, 2, 2, 2, 2, 3, 3],
                 [1, 1, 1, undefined, 2, 2, 2, undefined, 3, 3]}
            ]].

table(Specs, Cells) ->
    Columns = [#table_col{id = Id, header = Cell, width = Spec}
               || {Id, {Spec, Cell}} <- lists:zip(lists:seq(1, length(Specs)), lists:zip(Specs, Cells))],
    #table{id = table, columns = Columns, rows = [Cells], zebra = false,
           header_separator = false, clickable_columns = lists:seq(1, length(Specs))}.

widths(Table, Width) ->
    nit_el_table:column_widths(Table, Table#table.rows, Width).

%% Use a larger screen to catch writes beyond the viewport, plus nested offsets
%% and one-based mouse coordinates. Headers still own their following separator.
assert_geometry(Table0, ContentWidth, Expected, HeaderIds, CellIds) ->
    BO = case Table0#table.border of none -> 0; _ -> 1 end,
    Width = ContentWidth + 2 * BO,
    Table = Table0#table{x = 2, y = 1, width = Width, height = 2 + 2 * BO},
    Bounds = #bounds{x = 3, y = 2, width = Width + 2, height = 8},
    X = Bounds#bounds.x + Table#table.x + BO,
    Y = Bounds#bounds.y + Table#table.y + BO,
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), Width + 10, 12),
    ?assertEqual(ContentWidth, string:length(Expected)),
    ?assertEqual(Expected, row_text(Screen, X, Y, ContentWidth)),
    ?assertEqual(Expected, row_text(Screen, X, Y + 1, ContentWidth)),
    ?assertEqual(ContentWidth, length(HeaderIds)),
    ?assertEqual(ContentWidth, length(CellIds)),
    lists:foreach(fun({Offset, {HeaderId, CellId}}) ->
        HeaderHit = case HeaderId of
            undefined -> {table, table};
            _ -> {table_header, table, HeaderId}
        end,
        CellHit = case CellId of
            undefined -> {table_row, table, 1};
            _ -> {table_cell, table, 1, CellId}
        end,
        ?assertEqual(HeaderHit, nit_hit:find_at(Table, X + Offset, Y + 1, Bounds)),
        ?assertEqual(CellHit, nit_hit:find_at(Table, X + Offset, Y + 2, Bounds))
    end, lists:zip(lists:seq(1, ContentWidth), lists:zip(HeaderIds, CellIds))),
    OutsideX = Bounds#bounds.x + Table#table.x + Width,
    lists:foreach(fun(Row) ->
        ?assertMatch({$\s, #{}}, nit_screen:get_cell(Screen, OutsideX, Row)),
        ?assertEqual(not_found, nit_hit:find_at(Table, OutsideX + 1, Row + 1, Bounds))
    end, [Y, Y + 1]).

row_text(Screen, X, Y, Width) ->
    unicode:characters_to_binary([Char || Col <- lists:seq(X, X + Width - 1),
                                        {Char, _Style} <- [nit_screen:get_cell(Screen, Col, Y)]]).
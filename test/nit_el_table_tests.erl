-module(nit_el_table_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

keyed_selection_follows_reorder_test() ->
    Old = #table{id = table, rows = [[1], [2], [3]], row_keys = [a, b, c], selected_row = 2},
    New = Old#table{rows = [[30], [10], [20]], row_keys = [c, a, b], selected_row = 1},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(3, Merged#table.selected_row),
    ?assertEqual([20], nit_engine:table_row_data(Merged, Merged#table.selected_row)).

removed_key_clears_selection_test() ->
    Old = #table{id = table, rows = [[1], [2], [3]], row_keys = [a, b, c],
                 selected_row = 2, scroll_offset = 2},
    New = Old#table{rows = [[30]], row_keys = [c]},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(0, Merged#table.selected_row),
    ?assertEqual(0, Merged#table.scroll_offset),
    ?assertEqual([], nit_engine:table_row_data(Merged, 0)),
    ?assertMatch(#table{selected_row = 1}, nit_nav:navigate_table(down, Merged)).

no_selection_stays_none_test() ->
    lists:foreach(fun(Keys) ->
        Old = #table{id = table, sortable = true, rows = [[1], [2]], row_keys = Keys},
        New = Old#table{selected_row = 2},
        ?assertMatch(#table{selected_row = 0}, nit_tree:merge_state(Old, New))
    end, [[], [a, b]]).

unkeyed_static_selection_clamps_on_shrink_test() ->
    Old = #table{id = table, rows = [[1], [2], [3]], selected_row = 3, scroll_offset = 50},
    New = Old#table{rows = [[4], [5]], height = 3, header_separator = false},
    ?assertMatch(#table{selected_row = 2, scroll_offset = 0}, nit_tree:merge_state(Old, New)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0},
                 nit_tree:merge_state(Old, New#table{rows = []})).

keyed_virtual_selection_uses_absolute_keys_test() ->
    Provider = fun(_, _) -> error(merge_must_not_fetch_rows) end,
    Old = #table{id = table, total_rows = 5, row_provider = Provider,
                 row_keys = [a, b, c, d, e], selected_row = 5, scroll_offset = 3},
    New = Old#table{total_rows = 3, row_keys = [e, c, a]},
    ?assertMatch(#table{selected_row = 1, scroll_offset = 2}, nit_tree:merge_state(Old, New)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 1},
                 nit_tree:merge_state(Old, New#table{total_rows = 2, row_keys = [a, c]})),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0},
                 nit_tree:merge_state(Old, New#table{total_rows = 0, row_keys = []})).

unkeyed_virtual_selection_clamps_on_shrink_test() ->
    Old = #table{id = table, total_rows = 100, selected_row = 99, scroll_offset = 95},
    New = Old#table{total_rows = 3, height = 4, header_separator = false},
    ?assertMatch(#table{selected_row = 3, scroll_offset = 0}, nit_tree:merge_state(Old, New)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0},
                 nit_tree:merge_state(Old, New#table{total_rows = 0})).

controlled_selection_scroll_and_sort_win_test() ->
    Old = #table{id = table, columns = [#table_col{id = value}],
                 rows = [[30], [20], [10]], row_keys = [c, b, a], sortable = true,
                 selected_row = 3, scroll_offset = 2, sort_by = value, sort_dir = desc},
    New = Old#table{controlled = true, rows = [[10], [20], [30]], row_keys = [a, b, c],
                    selected_row = 1, scroll_offset = 1, sort_by = value, sort_dir = asc},
    ?assertEqual(New, nit_tree:merge_state(Old, New)),
    Cleared = New#table{selected_row = 0, scroll_offset = 0, sort_by = undefined},
    ?assertEqual(Cleared, nit_tree:merge_state(Old, Cleared)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0, sort_by = undefined},
                 nit_tree:merge_state(Old, Cleared#table{rows = [], row_keys = [],
                                                        selected_row = 9, scroll_offset = 9})).

keyed_builtin_sort_keeps_keys_parallel_test() ->
    Table = #table{id = table, sortable = true, columns = [#table_col{id = value}],
                   rows = [[20], [10], [30]], row_keys = [b, a, c], selected_row = 1},
    Sorted = nit_el_table:toggle_sort(Table, value),
    ?assertEqual([[30], [20], [10]], Sorted#table.rows),
    ?assertEqual([c, b, a], Sorted#table.row_keys),
    ?assertEqual(2, Sorted#table.selected_row),
    Asc = nit_el_table:toggle_sort(Sorted, value),
    ?assertEqual([[10], [20], [30]], Asc#table.rows),
    ?assertEqual([a, b, c], Asc#table.row_keys),
    New = Table#table{rows = [[40], [50], [60]], row_keys = [c, a, b]},
    Merged = nit_tree:merge_state(Sorted, New),
    ?assertEqual([[60], [50], [40]], Merged#table.rows),
    ?assertEqual([b, a, c], Merged#table.row_keys),
    ?assertEqual(1, Merged#table.selected_row).

unkeyed_sort_defaults_unchanged_test() ->
    Table = #table{sortable = true, columns = [#table_col{id = value}], rows = [[1], [3], [2]]},
    Sorted = nit_el_table:toggle_sort(Table, value),
    ?assertMatch(#table{rows = [[3], [2], [1]], row_keys = [], selected_row = 1,
                        sort_by = value, sort_dir = desc, scroll_offset = 0}, Sorted),
    ?assertEqual(Table, nit_el_table:toggle_sort(Table, unknown)).

empty_virtual_table_never_calls_provider_test() ->
    Table = #table{id = table, total_rows = 0, scroll_offset = 50, width = 10, height = 4,
                   columns = [#table_col{id = col, header = <<"Col">>}],
                   row_provider = fun(_, _) -> error(empty_provider_call) end},
    Bounds = #bounds{width = 10, height = 4},
    ?assertEqual([], nit_el_table:visible_rows(Table, 3)),
    ?assertEqual(0, nit_el_table:clamp_scroll_offset(Table, 3)),
    ?assert(is_binary(iolist_to_binary(nit_el_table:render(Table, Bounds, #{})))),
    ?assertEqual({table, table}, nit_hit:find_at(Table, 1, 3, Bounds)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0}, nit_nav:navigate_table(down, Table)),
    ?assertMatch(#table{selected_row = 0, scroll_offset = 0}, nit_nav:navigate_table(up, Table)).

virtual_fetch_clamps_offset_and_count_test() ->
    Table = #table{id = table, total_rows = 2, scroll_offset = 99, width = 8, height = 5,
                   header_separator = false, columns = [#table_col{id = col}],
                   row_provider = fun(Start, Count) ->
                       ?assertEqual({0, 2}, {Start, Count}),
                       [[<<"one">>], [<<"two">>]]
                   end},
    Bounds = #bounds{width = 8, height = 5},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), 8, 5),
    ?assertEqual(<<"one     ">>, row_text(Screen, 8, 1)),
    ?assertEqual(<<"two     ">>, row_text(Screen, 8, 2)),
    ?assertEqual({table_row, table, 1}, nit_hit:find_at(Table, 1, 2, Bounds)),
    ?assertEqual({table_row, table, 2}, nit_hit:find_at(Table, 1, 3, Bounds)).

zero_viewport_skips_virtual_provider_test() ->
    Table = #table{total_rows = 2, height = 2, row_provider = fun(_, _) -> error(zero_count) end},
    ?assertEqual([], nit_el_table:visible_rows(Table, 0)),
    ?assert(is_binary(iolist_to_binary(nit_el_table:render(Table, #bounds{}, #{})))).

dense_header_style_and_coordinates_test() ->
    Table = dense_table(),
    Bounds = #bounds{width = 12, height = 4},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), 12, 4),
    ?assertEqual(<<"Name│N      "/utf8>>, row_text(Screen, 12, 0)),
    ?assertEqual(<<"one │1      "/utf8>>, row_text(Screen, 12, 1)),
    ?assertEqual(<<"two │2      "/utf8>>, row_text(Screen, 12, 2)),
    {_, HeaderStyle} = nit_screen:get_cell(Screen, 11, 0),
    ?assertEqual(white, maps:get(bg, HeaderStyle)),
    ?assertEqual(black, maps:get(fg, HeaderStyle)),
    ?assertEqual(false, maps:get(bold, HeaderStyle, false)),
    {_, RowStyle} = nit_screen:get_cell(Screen, 0, 1),
    ?assertEqual(false, maps:is_key(bg, RowStyle)),
    ?assertEqual({table_header, table, name}, nit_hit:find_at(Table, 1, 1, Bounds)),
    %% Separator cells belong to the preceding header, preserving old semantics.
    ?assertEqual({table_header, table, name}, nit_hit:find_at(Table, 5, 1, Bounds)),
    ?assertEqual({table_header, table, count}, nit_hit:find_at(Table, 6, 1, Bounds)),
    ?assertEqual({table_row, table, 1}, nit_hit:find_at(Table, 1, 2, Bounds)).

multi_character_separator_layout_and_hit_test() ->
    Table = (dense_table())#table{column_separator = " | "},
    Bounds = #bounds{width = 12, height = 4},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), 12, 4),
    ?assertEqual(<<"Name | N    ">>, row_text(Screen, 12, 0)),
    ?assertEqual({table_header, table, name}, nit_hit:find_at(Table, 7, 1, Bounds)),
    ?assertEqual({table_header, table, count}, nit_hit:find_at(Table, 8, 1, Bounds)).

header_options_drive_height_and_navigation_test() ->
    Table = (dense_table())#table{height = auto},
    Bounds = #bounds{width = 12, height = 8},
    ?assertEqual(3, nit_el_table:height(Table, Bounds)),
    ?assertMatch({ok, #bounds{height = 3}}, nit_bounds:find_element_bounds(Table, table, Bounds)),
    ?assertEqual(2, nit_engine:resolved_table_visible_height(Table, table, Table, Bounds)),
    ?assertEqual(4, nit_el_table:height(Table#table{header_separator = true}, Bounds)),
    ?assertEqual(2, nit_el_table:height(Table#table{show_header = false}, Bounds)),
    ?assertEqual(5, nit_el_table:height(Table#table{border = single}, Bounds)),
    Long = Table#table{height = 4, rows = [[N] || N <- lists:seq(1, 10)], selected_row = 3},
    ?assertEqual(3, nit_engine:default_table_visible_height(Long)),
    ?assertEqual(3, nit_engine:resolved_table_visible_height(Long, table, Long, Bounds)),
    ?assertEqual(3, nit_engine:page_lines_table(Long, table, Long, Bounds)),
    ?assertMatch(#table{selected_row = 4, scroll_offset = 1}, nit_nav:navigate_table(down, Long)),
    ?assertMatch(#table{selected_row = 1}, nit_nav:navigate_table(down, Long#table{selected_row = 0})).

default_header_render_unchanged_test() ->
    Table = #table{width = 8, height = 3, zebra = false,
                   columns = [#table_col{header = <<"A">>, width = 2},
                              #table_col{header = <<"B">>, width = 2}], rows = [[1, 2]]},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, #bounds{}, #{}), 8, 3),
    ?assertEqual(<<"A  B    ">>, row_text(Screen, 8, 0)),
    ?assertEqual(binary:copy(<<"─"/utf8>>, 8), row_text(Screen, 8, 1)),
    ?assertEqual(<<"1  2    ">>, row_text(Screen, 8, 2)),
    {_, Style} = nit_screen:get_cell(Screen, 0, 0),
    ?assertEqual(true, maps:get(bold, Style)).

dense_bordered_header_coordinates_test() ->
    Table = (dense_table())#table{x = 2, y = 1, border = single, height = 5},
    Bounds = #bounds{x = 1, y = 1, width = 20, height = 10},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), 20, 10),
    %% Table origin (3,2), header origin (4,3); screen cells are zero-based.
    ?assertMatch({$N, _}, nit_screen:get_cell(Screen, 4, 3)),
    ?assertMatch({$o, _}, nit_screen:get_cell(Screen, 4, 4)),
    %% Hit coordinates are terminal mouse coordinates, i.e. one-based.
    ?assertEqual({table_header, table, name}, nit_hit:find_at(Table, 5, 4, Bounds)),
    ?assertEqual({table_row, table, 1}, nit_hit:find_at(Table, 5, 5, Bounds)).

dimmed_virtual_table_uses_dense_layout_test() ->
    Base = dense_table(),
    Table = Base#table{rows = [], total_rows = 2,
                       row_provider = fun(Start, Count) ->
                           ?assertEqual({0, 2}, {Start, Count}),
                           Base#table.rows
                       end},
    Bounds = #bounds{width = 12, height = 4},
    Normal = nit_screen:from_ansi(nit_render:render(Table, Bounds), 12, 4),
    Dimmed = nit_screen:from_ansi(nit_render:render_dimmed(Table, Bounds, table), 12, 4),
    lists:foreach(fun(Row) ->
        ?assertEqual(row_text(Normal, 12, Row), row_text(Dimmed, 12, Row))
    end, lists:seq(0, 3)),
    {_, Style} = nit_screen:get_cell(Dimmed, 0, 1),
    ?assertEqual(true, maps:get(dim, Style)).

narrow_table_clips_columns_to_content_width_test() ->
    Table = (dense_table())#table{width = 4},
    Bounds = #bounds{width = 8, height = 4},
    Screen = nit_screen:from_ansi(nit_el_table:render(Table, Bounds, #{}), 8, 4),
    ?assertEqual(<<"Nam│    "/utf8>>, row_text(Screen, 8, 0)),
    lists:foreach(fun(Row) ->
        lists:foreach(fun(Col) ->
            ?assertMatch({$\s, #{}}, nit_screen:get_cell(Screen, Col, Row))
        end, lists:seq(4, 7))
    end, lists:seq(0, 3)).

dense_table() ->
    #table{id = table, width = 12, height = 4, zebra = false,
           header_separator = false, column_separator = <<"│"/utf8>>,
           header_style = #{bg => white, fg => black, bold => false},
           columns = [#table_col{id = name, header = <<"Name">>, width = 4},
                      #table_col{id = count, header = <<"N">>, width = 3}],
           rows = [[<<"one">>, 1], [<<"two">>, 2]]}.

row_text(Screen, Width, Row) ->
    unicode:characters_to_binary([
        Char || Col <- lists:seq(0, Width - 1),
                {Char, _Style} <- [nit_screen:get_cell(Screen, Col, Row)]
    ]).
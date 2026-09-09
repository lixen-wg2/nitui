-module(nit_table_cell_hit_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

cell_width_includes_alignment_padding_not_separators_test_() ->
    [?_test(begin
        Table = (table())#table{column_separator = Separator,
                                columns = [#table_col{id = name, width = 4, align = Align},
                                           #table_col{id = count, width = 3}]},
        SepWidth = nit_el_table:column_separator_width(Table),
        lists:foreach(fun(Col) ->
            ?assertEqual({table_cell, rows, 1, name}, hit(Table, Col, 2))
        end, lists:seq(1, 4)),
        lists:foreach(fun(Col) ->
            ?assertEqual({table_row, rows, 1}, hit(Table, Col, 2))
        end, lists:seq(5, 20)),
        Both = Table#table{clickable_columns = [name, count]},
        ?assertEqual({table_cell, rows, 1, count}, hit(Both, 5 + SepWidth, 2)),
        ?assertEqual({table_cell, rows, 1, count}, hit(Both, 7 + SepWidth, 2)),
        ?assertEqual({table_row, rows, 1}, hit(Both, 8 + SepWidth, 2))
    end) || Align <- [left, center, right], Separator <- [" ", " | ", <<"│"/utf8>>, <<>>]].

headers_borders_and_nested_offsets_test_() ->
    [?_test(begin
        Table = (table())#table{x = 3, y = 2, border = Border,
                                show_header = ShowHeader, header_separator = Rule},
        Bounds = #bounds{x = 10, y = 5, width = 30, height = 10},
        BO = case Border of none -> 0; _ -> 1 end,
        HeaderHeight = nit_el_table:header_height(Table),
        ?assertEqual({table_cell, rows, 1, name},
                     nit_hit:find_at(Table, 14 + BO, 8 + BO + HeaderHeight, Bounds)),
        %% Every header/border coordinate keeps the pre-opt-in hit contract.
        Old = Table#table{clickable_columns = []},
        lists:foreach(fun({Col, Row}) ->
            ?assertEqual(nit_hit:find_at(Old, Col, Row, Bounds),
                         nit_hit:find_at(Table, Col, Row, Bounds))
        end, [{C, R} || C <- lists:seq(13, 33),
                       R <- lists:seq(7, 7 + BO + HeaderHeight)])
    end) || Border <- [none, single],
            {ShowHeader, Rule} <- [{false, false}, {true, false}, {true, true}]].

auto_widths_include_sort_indicator_and_visible_data_test() ->
    Table = (table())#table{sortable = true, sort_by = name,
                            columns = [#table_col{id = name, header = <<"N">>},
                                       #table_col{id = count, header = <<"C">>}],
                            rows = [[<<"longname">>, 1]], clickable_columns = [count]},
    ?assertEqual([8, 1], nit_el_table:column_widths(Table, Table#table.rows, 20)),
    ?assertEqual({table_row, rows, 1}, hit(Table, 9, 2)),
    ?assertEqual({table_cell, rows, 1, count}, hit(Table, 10, 2)),
    ?assertEqual({table_header, rows, count}, hit(Table, 10, 1)),
    Short = Table#table{rows = [[<<"x">>, 1]]},
    ?assertEqual([3, 1], nit_el_table:column_widths(Short, Short#table.rows, 20)),
    ?assertEqual({table_cell, rows, 1, count}, hit(Short, 5, 2)).

auto_fill_and_fixed_table_widths_use_local_offsets_test_() ->
    [?_test(begin
        Table = (table())#table{x = 2, y = 1, width = Width, height = fill},
        Bounds = #bounds{x = 3, y = 2, width = 20, height = 5},
        ?assertEqual({table_cell, rows, 1, name}, nit_hit:find_at(Table, 6, 5, Bounds)),
        ?assertEqual({table_row, rows, 1}, nit_hit:find_at(Table, 10, 5, Bounds)),
        ?assertEqual({table_header, rows, count}, nit_hit:find_at(Table, 11, 4, Bounds))
    end) || Width <- [auto, fill, 18]].

clickable_flag_does_not_change_rendering_test() ->
    Table = (table())#table{selected_row = 1},
    Bounds = #bounds{width = 20, height = 5},
    lists:foreach(fun(Focused) ->
        Opts = #{focused => Focused},
        ?assertEqual(nit_el_table:render(Table#table{clickable_columns = []}, Bounds, Opts),
                     nit_el_table:render(Table, Bounds, Opts))
    end, [false, true]).

scaled_columns_stop_at_rendered_table_edge_test() ->
    Table = (table())#table{width = 7, column_separator = " | ",
                            clickable_columns = [name, count]},
    ?assertEqual([3, 3], nit_el_table:column_widths(Table, Table#table.rows, 7)),
    ?assertEqual({table_cell, rows, 1, name}, hit(Table, 3, 2)),
    ?assertEqual({table_row, rows, 1}, hit(Table, 6, 2)),
    ?assertEqual({table_cell, rows, 1, count}, hit(Table, 7, 2)),
    ?assertEqual(not_found, hit(Table, 8, 2)).

static_and_virtual_scroll_offsets_are_clamped_test_() ->
    [?_test(begin
        Rows = [[N, N] || N <- lists:seq(1, 10)],
        Base = (table())#table{height = 2, show_header = false, rows = Rows,
                               scroll_offset = Offset},
        Table = case Virtual of
            false -> Base;
            true -> Base#table{rows = [], total_rows = 10,
                                row_provider = fun(Start, Count) ->
                                    lists:sublist(lists:nthtail(Start, Rows), Count)
                                end}
        end,
        ?assertEqual({table_cell, rows, First, name}, hit(Table, 1, 1)),
        ?assertEqual({table_cell, rows, First + 1, name}, hit(Table, 1, 2)),
        ?assertEqual(not_found, hit(Table, 1, 3))
    end) || {Offset, First} <- [{-2, 1}, {3, 4}, {99, 9}], Virtual <- [false, true]].

empty_invalid_and_outside_hits_retain_old_behavior_test() ->
    Base = table(),
    Tables = [Base#table{clickable_columns = []},
              Base#table{clickable_columns = [unknown]}, Base#table{rows = []},
              Base#table{columns = []}, Base#table{visible = false},
              Base#table{rows = [], total_rows = 10, row_provider = fun(_, _) -> [] end}],
    lists:foreach(fun(Table) ->
        lists:foreach(fun({Col, Row}) ->
            ?assertEqual(hit(Table#table{clickable_columns = []}, Col, Row),
                         hit(Table, Col, Row))
        end, [{C, R} || C <- lists:seq(-1, 21), R <- lists:seq(-1, 6)])
    end, Tables),
    lists:foreach(fun({Col, Row}) ->
        ?assertEqual(hit(Base#table{clickable_columns = []}, Col, Row), hit(Base, Col, Row))
    end, [{0, 0}, {1, 1}, {1, 4}, {1, 5}, {1, 6}, {21, 2}, {-1, 2}]).

cell_hits_are_clipped_to_allocated_bounds_test() ->
    Table = (table())#table{show_header = false},
    Bounds = #bounds{width = 3, height = 1},
    ?assertEqual({table_cell, rows, 1, name}, nit_hit:find_at(Table, 3, 1, Bounds)),
    %% Neither cells nor fallback row hits may escape the allocated viewport.
    ?assertEqual(not_found, nit_hit:find_at(Table, 4, 1, Bounds)),
    ?assertEqual(not_found, nit_hit:find_at(Table, 1, 2, Bounds)).

scroll_container_clips_and_translates_cell_hits_test() ->
    Table = (table())#table{height = 10, show_header = false,
                            rows = [[N, N] || N <- lists:seq(1, 10)]},
    Scroll = #scroll{id = viewport, width = 10, height = 2, offset = 3,
                     focusable = true, children = [Table]},
    ?assertEqual({table_cell, rows, 4, name}, hit(Scroll, 1, 1)),
    ?assertEqual({table_cell, rows, 5, name}, hit(Scroll, 1, 2)),
    ?assertEqual({scroll, viewport}, hit(Scroll, 10, 1)),
    ?assertEqual(not_found, hit(Scroll, 1, 3)).

table() ->
    #table{id = rows, width = 20, height = 5, header_separator = false,
           columns = [#table_col{id = name, header = <<"Name">>, width = 4},
                      #table_col{id = count, header = <<"N">>, width = 3}],
           rows = [[<<"x">>, 1], [<<"y">>, 2]], clickable_columns = [name]}.

hit(Table, Col, Row) ->
    nit_hit:find_at(Table, Col, Row, #bounds{width = 80, height = 24}).
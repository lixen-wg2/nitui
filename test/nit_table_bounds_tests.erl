-module(nit_table_bounds_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

table_uses_one_based_mouse_coordinates_test_() ->
    [?_test(begin
        T = #table{id = rows, x = 2, y = 1, width = 12, height = 6,
            border = Border, show_header = Header, header_separator = Rule,
            columns = [#table_col{id = value, width = 8}], rows = [[<<"fixture">>]]},
        B = #bounds{x = 10, y = 5, width = 30, height = 20},
        lists:foreach(fun({C, R}) ->
            ?assertEqual(not_found, nit_hit:find_at(T, C, R, B))
        end, [{C, R} || C <- lists:seq(12, 25), R <- [6, 13]] ++
             [{C, R} || C <- [12, 25], R <- lists:seq(6, 13)]),
        BO = case Border of none -> 0; _ -> 1 end,
        DataRow = 7 + BO + nit_el_table:header_height(T),
        ?assertEqual({table_row, rows, 1}, nit_hit:find_at(T, 13 + BO, DataRow, B)),
        case Border of
            none -> ok;
            _ ->
                ?assertEqual({table, rows}, nit_hit:find_at(T, 13, DataRow, B)),
                ?assertEqual({table, rows}, nit_hit:find_at(T, 24, DataRow, B)),
                ?assertEqual({table, rows}, nit_hit:find_at(T, 13, 7, B))
        end
    end) || Border <- [none, single, double],
            {Header, Rule} <- [{false, false}, {true, false}, {true, true}]].

table_cannot_claim_surrounding_frame_without_scroll_wrapper_test() ->
    T = #table{id = rows, height = fill, columns = [#table_col{id = value}],
        rows = [[<<"fixture">>]]},
    Root = #box{border = single, children = [#vbox{children = [T]}]},
    B = #bounds{width = 20, height = 10},
    lists:foreach(fun({C, R}) ->
        ?assertEqual(not_found, nit_hit:find_at(Root, C, R, B))
    end, [{C, R} || C <- lists:seq(1, 20), R <- [1, 10]] ++
         [{C, R} || C <- [1, 20], R <- lists:seq(1, 10)]),
    ?assertEqual({table_header, rows, value}, nit_hit:find_at(Root, 2, 2, B)),
    ?assertEqual({table_row, rows, 1}, nit_hit:find_at(Root, 2, 4, B)).

hidden_and_parent_clipped_tables_are_not_hit_test() ->
    T = #table{id = rows, width = 40, height = 20,
        columns = [#table_col{id = value}], rows = [[<<"fixture">>]]},
    B = #bounds{x = 2, y = 3, width = 10, height = 5},
    ?assertEqual(not_found, nit_hit:find_at(T, 13, 6, B)),
    ?assertEqual(not_found, nit_hit:find_at(T, 3, 9, B)),
    ?assertEqual(not_found, nit_hit:find_at(T#table{visible = false}, 3, 6, B)).
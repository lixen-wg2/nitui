%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_nav module.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_nav_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

navigate_table_cleared_selection_returns_to_first_row_test() ->
    Table = #table{rows = [[N] || N <- lists:seq(1, 20)], selected_row = 0,
                   scroll_offset = 15, height = 5, show_header = false},
    ?assertMatch(#table{selected_row = 1, scroll_offset = 0}, nit_nav:navigate_table(down, Table)),
    ?assertMatch(#table{selected_row = 1, scroll_offset = 0}, nit_nav:navigate_table(up, Table)).

navigate_table_reordered_selection_becomes_visible_test() ->
    Table = #table{rows = [[N] || N <- lists:seq(1, 20)], selected_row = 18,
                   scroll_offset = 0, height = 5, show_header = false},
    ?assertMatch(#table{selected_row = 19, scroll_offset = 14}, nit_nav:navigate_table(down, Table)),
    ?assertMatch(#table{selected_row = 17, scroll_offset = 12}, nit_nav:navigate_table(up, Table)).

navigate_table_respects_borderless_height_test() ->
    Table = #table{
        rows = lists:duplicate(10, [<<"row">>]),
        height = 8,
        border = none,
        show_header = false,
        selected_row = 5,
        scroll_offset = 0
    },
    NewTable = nit_nav:navigate_table(down, Table),
    ?assertEqual(6, NewTable#table.selected_row),
    ?assertEqual(0, NewTable#table.scroll_offset).

navigate_table_scales_with_borders_test() ->
    Table = #table{
        rows = lists:duplicate(10, [<<"row">>]),
        height = 8,
        border = single,
        show_header = true,
        selected_row = 4,
        scroll_offset = 0
    },
    NewTable = nit_nav:navigate_table(down, Table),
    ?assertEqual(5, NewTable#table.selected_row),
    ?assertEqual(1, NewTable#table.scroll_offset).

navigate_table_uses_explicit_visible_height_test() ->
    Table = #table{
        rows = lists:duplicate(20, [<<"row">>]),
        height = auto,
        border = none,
        show_header = true,
        selected_row = 5,
        scroll_offset = 0
    },
    NewTable = nit_nav:navigate_table(down, 1, 5, Table),
    ?assertEqual(6, NewTable#table.selected_row),
    ?assertEqual(1, NewTable#table.scroll_offset).

navigate_empty_list_stays_valid_test() ->
    List = #list{items = [], selected = 0, offset = 0},
    NewList = nit_nav:navigate_list(down, List),
    ?assertEqual(0, NewList#list.selected),
    ?assertEqual(0, NewList#list.offset).

navigate_list_uses_explicit_visible_height_test() ->
    List = #list{
        items = [<<"a">>, <<"b">>, <<"c">>, <<"d">>, <<"e">>, <<"f">>],
        selected = 0,
        offset = 0,
        height = auto
    },
    NewList = nit_nav:navigate_list(down, 3, 3, List),
    ?assertEqual(3, NewList#list.selected),
    ?assertEqual(3, NewList#list.offset).

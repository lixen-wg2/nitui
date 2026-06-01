%%%-------------------------------------------------------------------
%%% @doc Unit tests for iso_hit module.
%%%
%%% Tests hit testing functionality including:
%%% - Button hit detection
%%% - Input hit detection
%%% - Table and table row hit detection
%%% - Tabs and tab bar hit detection
%%% - Box container hit detection
%%% - Nested element hit detection
%%% @end
%%%-------------------------------------------------------------------
-module(iso_hit_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

%%====================================================================
%% Test helpers
%%====================================================================

%% Standard bounds for testing
default_bounds() ->
    #bounds{x = 0, y = 0, width = 80, height = 24}.

%%====================================================================
%% Button hit tests
%%====================================================================

button_hit_test() ->
    Tree = #button{id = my_btn, x = 5, y = 2, label = <<"Click">>},
    Bounds = default_bounds(),
    %% Button is at row 3 (y=2 + 1), cols 6-14 (x=5 + 1 to x+width)
    ?assertEqual({button, my_btn}, iso_hit:find_at(Tree, 8, 3, Bounds)).

button_miss_above_test() ->
    Tree = #button{id = my_btn, x = 5, y = 2, label = <<"Click">>},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 8, 2, Bounds)).

button_miss_left_test() ->
    Tree = #button{id = my_btn, x = 5, y = 2, label = <<"Click">>},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 5, 3, Bounds)).

button_miss_right_test() ->
    Tree = #button{id = my_btn, x = 5, y = 2, width = 10, label = <<"Click">>},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 20, 3, Bounds)).

%%====================================================================
%% Input hit tests
%%====================================================================

input_hit_test() ->
    Tree = #input{id = my_input, x = 10, y = 5, width = 20},
    Bounds = default_bounds(),
    %% Input is at row 6 (y=5 + 1), cols 11-30 (x=10 + 1 to x+width)
    ?assertEqual({input, my_input}, iso_hit:find_at(Tree, 15, 6, Bounds)).

input_miss_test() ->
    Tree = #input{id = my_input, x = 10, y = 5, width = 20},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 5, 6, Bounds)).

%%====================================================================
%% Table hit tests
%%====================================================================

table_hit_row_test() ->
    Tree = #table{id = my_table, x = 0, y = 0, width = 40, height = 10,
                  border = single, show_header = true,
                  columns = [#table_col{header = <<"Col">>}],
                  rows = [[<<"Row 1">>], [<<"Row 2">>], [<<"Row 3">>]]},
    Bounds = default_bounds(),
    %% Row 1 data starts at y=0 + border(1) + header(2) + 1 = row 4
    ?assertEqual({table_row, my_table, 1}, iso_hit:find_at(Tree, 5, 4, Bounds)).

table_hit_second_row_test() ->
    Tree = #table{id = my_table, x = 0, y = 0, width = 40, height = 10,
                  border = single, show_header = true,
                  columns = [#table_col{header = <<"Col">>}],
                  rows = [[<<"Row 1">>], [<<"Row 2">>], [<<"Row 3">>]]},
    Bounds = default_bounds(),
    ?assertEqual({table_row, my_table, 2}, iso_hit:find_at(Tree, 5, 5, Bounds)).

table_hit_header_test() ->
    Tree = #table{id = my_table, x = 0, y = 0, width = 40, height = 10,
                  border = single, show_header = true,
                  columns = [
                      #table_col{id = pid, header = <<"PID">>, width = 12},
                      #table_col{id = mem, header = <<"Memory">>, width = 10}
                  ],
                  rows = [[<<"<0.1.0>">>, <<"45 KB">>]]},
    Bounds = default_bounds(),
    ?assertEqual({table_header, my_table, pid}, iso_hit:find_at(Tree, 5, 2, Bounds)),
    ?assertEqual({table_header, my_table, mem}, iso_hit:find_at(Tree, 16, 2, Bounds)).

table_hit_border_test() ->
    Tree = #table{id = my_table, x = 0, y = 0, width = 40, height = 10,
                  border = single, show_header = true,
                  columns = [#table_col{header = <<"Col">>}],
                  rows = [[<<"Row 1">>]]},
    Bounds = default_bounds(),
    %% Clicking on border area returns table (not table_row)
    ?assertEqual({table, my_table}, iso_hit:find_at(Tree, 0, 0, Bounds)).

table_miss_test() ->
    Tree = #table{id = my_table, x = 5, y = 5, width = 20, height = 5,
                  columns = [], rows = []},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 1, 1, Bounds)).

virtual_table_hit_row_test() ->
    Tree = #table{id = virtual_table, x = 0, y = 0, width = 40, height = 10,
                  border = single, show_header = true, rows = [],
                  total_rows = 1000,
                  columns = [#table_col{header = <<"Col">>}]},
    Bounds = default_bounds(),
    ?assertEqual({table_row, virtual_table, 1}, iso_hit:find_at(Tree, 5, 4, Bounds)).

tree_hit_node_test() ->
    Tree = #tree{
        id = my_tree,
        x = 0,
        y = 0,
        height = 2,
        nodes = [
            #tree_node{id = root, label = <<"Root">>, expanded = true,
                       children = [#tree_node{id = child, label = <<"Child">>}]}
        ]
    },
    Bounds = default_bounds(),
    ?assertEqual({tree_toggle, my_tree, root}, iso_hit:find_at(Tree, 2, 1, Bounds)),
    ?assertEqual({tree_node, my_tree, root}, iso_hit:find_at(Tree, 5, 1, Bounds)),
    ?assertEqual({tree_node, my_tree, child}, iso_hit:find_at(Tree, 3, 2, Bounds)).

%%====================================================================
%% Box hit tests
%%====================================================================

box_hit_child_test() ->
    Tree = #box{id = my_box, x = 0, y = 0, width = 30, height = 10,
                focusable = true, children = [
                    #button{id = inner_btn, x = 2, y = 2, label = <<"Inner">>}
                ]},
    Bounds = default_bounds(),
    %% Borderless box passes bounds through unchanged (matches render in
    %% iso_el_box). Button at x=2,y=2 with label "Inner" renders at row 3,
    %% cols 3-11. Should find the child button, not the box.
    ?assertEqual({button, inner_btn}, iso_hit:find_at(Tree, 5, 3, Bounds)).

box_hit_empty_space_test() ->
    Tree = #box{id = my_box, x = 0, y = 0, width = 30, height = 10,
                focusable = true, children = []},
    Bounds = default_bounds(),
    %% Clicking empty space in focusable box returns box
    ?assertEqual({box, my_box}, iso_hit:find_at(Tree, 5, 5, Bounds)).

box_non_focusable_miss_test() ->
    Tree = #box{id = my_box, x = 0, y = 0, width = 30, height = 10,
                focusable = false, children = []},
    Bounds = default_bounds(),
    %% Non-focusable box with no children returns not_found
    ?assertEqual(not_found, iso_hit:find_at(Tree, 5, 5, Bounds)).

%%====================================================================
%% Nested element hit tests
%%====================================================================

nested_in_vbox_test() ->
    Tree = #vbox{x = 0, y = 0, children = [
        #button{id = btn1, x = 0, y = 0, label = <<"First">>},
        #button{id = btn2, x = 0, y = 0, label = <<"Second">>}
    ]},
    Bounds = default_bounds(),
    %% First button at row 1
    ?assertEqual({button, btn1}, iso_hit:find_at(Tree, 3, 1, Bounds)).

nested_in_panel_test() ->
    Tree = #panel{children = [
        #button{id = panel_btn, x = 5, y = 5, label = <<"Panel Button">>}
    ]},
    Bounds = default_bounds(),
    ?assertEqual({button, panel_btn}, iso_hit:find_at(Tree, 8, 6, Bounds)).

hbox_auto_children_share_width_hit_test() ->
    Tree = #hbox{children = [
        #box{id = left_box, focusable = true, height = 3, children = []},
        #box{id = right_box, focusable = true, height = 3, children = []}
    ]},
    Bounds = #bounds{x = 0, y = 0, width = 20, height = 4},
    ?assertEqual({box, right_box}, iso_hit:find_at(Tree, 15, 2, Bounds)).

scroll_hit_respects_offset_and_child_stacking_test() ->
    Tree = #scroll{
        id = log_scroll,
        height = 2,
        offset = 1,
        children = [
            #button{id = btn1, label = <<"One">>},
            #button{id = btn2, label = <<"Two">>},
            #button{id = btn3, label = <<"Three">>}
        ]
    },
    Bounds = #bounds{x = 0, y = 0, width = 20, height = 2},
    ?assertEqual({button, btn2}, iso_hit:find_at(Tree, 2, 1, Bounds)),
    ?assertEqual({button, btn3}, iso_hit:find_at(Tree, 2, 2, Bounds)).

%%====================================================================
%% Not found tests
%%====================================================================

text_not_interactive_test() ->
    Tree = #text{content = <<"Hello">>},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 1, 1, Bounds)).

empty_vbox_test() ->
    Tree = #vbox{children = []},
    Bounds = default_bounds(),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 1, 1, Bounds)).

status_bar_item_hit_test() ->
    Tree = #status_bar{
        items = [
            {<<"H">>, <<"Home">>},
            {<<"Q">>, <<"Quit">>}
        ]
    },
    Bounds = default_bounds(),
    ?assertEqual({status_bar_item, <<"H">>}, iso_hit:find_at(Tree, 2, 1, Bounds)),
    ?assertEqual({status_bar_item, <<"H">>}, iso_hit:find_at(Tree, 6, 1, Bounds)),
    ?assertEqual(not_found, iso_hit:find_at(Tree, 8, 1, Bounds)).

status_bar_item_hit_in_vbox_with_spacer_test() ->
    Tree = #vbox{
        children = [
            #text{content = <<"Header">>},
            #spacer{},
            #status_bar{
                items = [
                    {<<"H">>, <<"Home">>},
                    {<<"Q">>, <<"Quit">>}
                ]
            }
        ]
    },
    Bounds = #bounds{x = 0, y = 0, width = 80, height = 10},
    ?assertEqual({status_bar_item, <<"H">>}, iso_hit:find_at(Tree, 2, 10, Bounds)).

unicode_status_bar_item_hit_test() ->
    Tree = #status_bar{
        items = [
            {"↑/↓", <<"Navigate">>},
            {<<"Q">>, <<"Quit">>}
        ]
    },
    Bounds = default_bounds(),
    ?assertEqual({status_bar_item, "↑/↓"}, iso_hit:find_at(Tree, 2, 1, Bounds)),
    ?assertEqual({status_bar_item, "↑/↓"}, iso_hit:find_at(Tree, 12, 1, Bounds)).

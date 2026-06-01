%%%-------------------------------------------------------------------
%%% @doc Unit tests for iso_bounds.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_bounds_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

find_table_bounds_inside_tabs_test() ->
    Tree = #tabs{
        id = demo_tabs,
        height = 10,
        tabs = [
            #tab{
                id = processes,
                label = <<"Processes">>,
                content = [
                    #table{
                        id = proc_table,
                        rows = lists:duplicate(20, [<<"row">>]),
                        columns = [#table_col{id = value, header = <<"Value">>}]
                    }
                ]
            }
        ],
        active_tab = processes
    },
    RootBounds = #bounds{x = 0, y = 0, width = 40, height = 24},
    {ok, TableBounds} = iso_bounds:find_element_bounds(Tree, proc_table, RootBounds),
    ?assertEqual(1, TableBounds#bounds.x),
    ?assertEqual(2, TableBounds#bounds.y),
    ?assertEqual(38, TableBounds#bounds.width),
    ?assertEqual(7, TableBounds#bounds.height).

find_button_bounds_inside_nested_vbox_with_spacer_test() ->
    Tree = #box{
        id = outer_box,
        y = 10,
        width = 20,
        height = 8,
        children = [
            #vbox{children = [
                #text{content = <<"Header">>},
                #spacer{},
                #button{id = bottom_btn, label = <<"Bottom">>}
            ]}
        ]
    },
    RootBounds = #bounds{x = 0, y = 0, width = 40, height = 30},
    {ok, ButtonBounds} = iso_bounds:find_element_bounds(Tree, bottom_btn, RootBounds),
    ?assertEqual(1, ButtonBounds#bounds.x),
    ?assertEqual(16, ButtonBounds#bounds.y),
    ?assertEqual(1, ButtonBounds#bounds.height).

find_auto_hbox_child_bounds_share_width_test() ->
    Tree = #hbox{children = [
        #box{id = left_box, focusable = true, height = 3, children = []},
        #box{id = right_box, focusable = true, height = 3, children = []}
    ]},
    RootBounds = #bounds{x = 0, y = 0, width = 20, height = 4},
    {ok, RightBounds} = iso_bounds:find_element_bounds(Tree, right_box, RootBounds),
    ?assertEqual(10, RightBounds#bounds.x),
    ?assertEqual(10, RightBounds#bounds.width).

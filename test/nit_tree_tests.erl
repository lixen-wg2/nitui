%%%-------------------------------------------------------------------
%%% @doc Unit tests for nit_tree state merging.
%%% @end
%%%-------------------------------------------------------------------
-module(nit_tree_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/nit_elements.hrl").

merge_list_preserves_offset_test() ->
    Old = #list{id = my_list, selected = 3, offset = 5, items = [<<"a">>, <<"b">>]},
    New = #list{id = my_list, selected = 0, offset = 0, items = [<<"c">>, <<"d">>]},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(3, Merged#list.selected),
    ?assertEqual(5, Merged#list.offset).

merge_input_preserves_selection_test() ->
    Old = #input{id = search, value = <<"abcdef">>, cursor_pos = 4,
                 selection_anchor = 1},
    New = #input{id = search, value = <<>>, cursor_pos = 0},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(<<"abcdef">>, Merged#input.value),
    ?assertEqual(4, Merged#input.cursor_pos),
    ?assertEqual(1, Merged#input.selection_anchor).

merge_sortable_table_preserves_selection_without_active_sort_test() ->
    Old = #table{
        id = my_table,
        sortable = true,
        selected_row = 4,
        scroll_offset = 2,
        rows = [[<<"a">>], [<<"b">>], [<<"c">>], [<<"d">>]]
    },
    New = #table{
        id = my_table,
        sortable = true,
        selected_row = 1,
        scroll_offset = 0,
        rows = [[<<"a">>], [<<"b">>], [<<"c">>], [<<"d">>]]
    },
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(4, Merged#table.selected_row),
    ?assertEqual(2, Merged#table.scroll_offset).

merge_tree_preserves_expanded_state_test() ->
    Old = #tree{
        id = my_tree,
        selected = child,
        offset = 2,
        nodes = [
            #tree_node{
                id = root,
                expanded = false,
                children = [#tree_node{id = child, expanded = false}]
            }
        ]
    },
    New = #tree{
        id = my_tree,
        selected = root,
        nodes = [
            #tree_node{
                id = root,
                expanded = true,
                children = [#tree_node{id = child, expanded = true}]
            }
        ]
    },
    Merged = nit_tree:merge_state(Old, New),
    [RootNode] = Merged#tree.nodes,
    [ChildNode] = RootNode#tree_node.children,
    ?assertEqual(child, Merged#tree.selected),
    ?assertEqual(2, Merged#tree.offset),
    ?assertEqual(false, RootNode#tree_node.expanded),
    ?assertEqual(false, ChildNode#tree_node.expanded).

merge_nested_scroll_inside_anonymous_layout_test() ->
    Old = #vbox{children = [
        #hbox{children = [
            #box{
                id = logs_box,
                children = [
                    #scroll{
                        id = log_scroll,
                        offset = 4,
                        children = [#text{content = <<"old">>}]
                    }
                ]
            }
        ]}
    ]},
    New = #vbox{children = [
        #hbox{children = [
            #box{
                id = logs_box,
                children = [
                    #scroll{
                        id = log_scroll,
                        offset = 0,
                        children = [#text{content = <<"new">>}]
                    }
                ]
            }
        ]}
    ]},
    Merged = nit_tree:merge_state(Old, New),
    [#hbox{children = [#box{children = [MergedScroll]}]}] = Merged#vbox.children,
    ?assertEqual(4, MergedScroll#scroll.offset).

merge_same_id_tabs_and_scroll_recurses_test() ->
    Old = #tabs{id = tabs, active_tab = second, tabs = [
        #tab{id = first, content = [#input{id = hidden, value = <<"typed">>, cursor_pos = 5}]},
        #tab{id = second, content = [#scroll{id = scroll, offset = 3, children = [
            #vbox{children = [
                #table{id = table, rows = [[1], [2]], selected_row = 2},
                #list{id = list, selected = 1, offset = 2},
                #text{id = label, content = <<"old">>}
            ]}
        ]}]}
    ]},
    New = #tabs{id = tabs, active_tab = first, tabs = [
        #tab{id = second, content = [#scroll{id = scroll, children = [
            #vbox{children = [
                #text{id = label, content = <<"fresh">>},
                #list{id = list},
                #table{id = table, rows = [[3], [4]]}
            ]}
        ]}]},
        #tab{id = first, content = [#input{id = hidden}]}
    ]},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(second, Merged#tabs.active_tab),
    ?assertMatch(#scroll{offset = 3}, nit_focus:find_element(Merged, scroll)),
    ?assertMatch(#table{selected_row = 2, rows = [[3], [4]]},
                 nit_focus:find_element(Merged, table)),
    ?assertMatch(#list{selected = 1, offset = 2}, nit_focus:find_element(Merged, list)),
    [#tab{content = [#scroll{children = [#vbox{children = [Label | _]}]}]},
     #tab{content = [Input]}] = Merged#tabs.tabs,
    ?assertMatch(#text{content = <<"fresh">>}, Label),
    ?assertMatch(#input{value = <<"typed">>, cursor_pos = 5}, Input).

merge_scroll_with_nested_tabs_recurses_test() ->
    Old = #scroll{id = outer, offset = 4, children = [
        #tabs{id = inner, active_tab = tab, tabs = [
            #tab{id = tab, content = [#input{id = input, value = <<"saved">>}]}
        ]}
    ]},
    New = #scroll{id = outer, children = [
        #tabs{id = inner, tabs = [#tab{id = tab, content = [#input{id = input}]}]}
    ]},
    Merged = nit_tree:merge_state(Old, New),
    ?assertEqual(4, Merged#scroll.offset),
    [#tabs{active_tab = Active, tabs = [#tab{content = [Input]}]}] = Merged#scroll.children,
    ?assertEqual(tab, Active),
    ?assertEqual(<<"saved">>, Input#input.value).

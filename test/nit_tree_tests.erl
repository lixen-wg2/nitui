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

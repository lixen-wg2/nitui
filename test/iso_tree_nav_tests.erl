%%%-------------------------------------------------------------------
%%% @doc Unit tests for tree navigation helpers.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tree_nav_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("nitui/include/iso_elements.hrl").

test_bounds() ->
    #bounds{x = 0, y = 0, width = 80, height = 24}.

simple_tree() ->
    #tree{
        id = nav_tree,
        height = 2,
        nodes = [
            #tree_node{id = node1, label = <<"Node 1">>},
            #tree_node{id = node2, label = <<"Node 2">>},
            #tree_node{id = node3, label = <<"Node 3">>}
        ]
    }.

navigate_without_selection_selects_first_node_test() ->
    Tree = simple_tree(),
    Navigated = iso_tree_nav:navigate(down, Tree, test_bounds()),
    ?assertEqual(node1, Navigated#tree.selected),
    ?assertEqual(0, Navigated#tree.offset).

navigate_down_scrolls_selected_node_into_view_test() ->
    Tree = simple_tree(),
    Navigated = iso_tree_nav:navigate(down, Tree#tree{selected = node2}, test_bounds()),
    ?assertEqual(node3, Navigated#tree.selected),
    ?assertEqual(1, Navigated#tree.offset).

toggle_left_on_child_selects_parent_test() ->
    Tree = #tree{
        id = nav_tree,
        nodes = [
            #tree_node{id = root, label = <<"Root">>, expanded = true,
                       children = [#tree_node{id = child, label = <<"Child">>}]}
        ],
        selected = child
    },
    Toggled = iso_tree_nav:toggle(left, Tree, test_bounds()),
    ?assertEqual(root, Toggled#tree.selected).

toggle_right_on_expanded_parent_selects_first_child_test() ->
    Tree = #tree{
        id = nav_tree,
        nodes = [
            #tree_node{id = root, label = <<"Root">>, expanded = true,
                       children = [#tree_node{id = child, label = <<"Child">>}]}
        ],
        selected = root
    },
    Toggled = iso_tree_nav:toggle(right, Tree, test_bounds()),
    ?assertEqual(child, Toggled#tree.selected).

toggle_selected_expands_collapsed_node_test() ->
    Tree = #tree{
        id = nav_tree,
        nodes = [
            #tree_node{id = root, label = <<"Root">>, expanded = false,
                       children = [#tree_node{id = child, label = <<"Child">>}]}
        ],
        selected = root
    },
    Toggled = iso_tree_nav:toggle_selected(Tree, test_bounds()),
    [RootNode] = Toggled#tree.nodes,
    ?assertEqual(true, RootNode#tree_node.expanded).

row_node_uses_offset_test() ->
    Tree = (simple_tree())#tree{offset = 1},
    ?assertEqual({ok, node2}, iso_tree_nav:row_node(Tree, test_bounds(), 1)),
    ?assertEqual({ok, node3}, iso_tree_nav:row_node(Tree, test_bounds(), 2)).

visible_nodes_respects_large_offset_test() ->
    Nodes = [
        #tree_node{id = {node, N}, label = integer_to_binary(N)}
        || N <- lists:seq(1, 100)
    ],
    Tree = #tree{id = nav_tree, height = 3, offset = 90, nodes = Nodes},
    Visible = iso_tree_nav:visible_nodes(Tree, test_bounds()),
    Ids = [Id || {_, _, #tree_node{id = Id}} <- Visible],
    ?assertEqual([{node, 91}, {node, 92}, {node, 93}], Ids).

navigate_page_down_moves_by_visible_height_test() ->
    Tree = #tree{
        id = nav_tree,
        nodes = [
            #tree_node{id = node1, label = <<"Node 1">>},
            #tree_node{id = node2, label = <<"Node 2">>},
            #tree_node{id = node3, label = <<"Node 3">>},
            #tree_node{id = node4, label = <<"Node 4">>}
        ],
        selected = node1,
        offset = 0
    },
    Navigated = iso_tree_nav:navigate(down, 2, 2, Tree),
    ?assertEqual(node3, Navigated#tree.selected),
    ?assertEqual(1, Navigated#tree.offset).

scroll_down_moves_view_without_changing_selection_test() ->
    Tree = (simple_tree())#tree{selected = node1, offset = 0},
    Scrolled = iso_tree_nav:scroll(down, 1, 2, Tree),
    ?assertEqual(node1, Scrolled#tree.selected),
    ?assertEqual(1, Scrolled#tree.offset).

scroll_clamps_offset_without_changing_selection_test() ->
    Tree = (simple_tree())#tree{selected = node1, offset = 1},
    Scrolled = iso_tree_nav:scroll(down, 10, 2, Tree),
    ?assertEqual(node1, Scrolled#tree.selected),
    ?assertEqual(1, Scrolled#tree.offset).
